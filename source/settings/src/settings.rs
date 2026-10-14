// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! What each row's value is, and what changing it does. `settings_ui.shcl` says
//! where a value lives; this says how it is read, shown and written.
//!
//! Wayfire takes a change as soon as its file changes, so an edit is written at
//! once and the desktop is the preview. The first value of each option touched
//! is kept, so Cancel can put it back. Apply only forgets those.

use crate::ui::{Key, Kind, Row, Setting, Ui};
use crate::wayfire::{SaveError, Wayfire};
use std::collections::HashMap;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
	Bool(bool),
	Num(f64),
	Text(String),
}

/// How a stored value is shown.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Conv {
	/// As stored. A dropdown shows the caption of the stored value.
	Plain,
	/// A fraction, shown as a whole percent.
	Percent,
	/// On while a timeout in seconds is above 0. Off stores -1.
	TimeoutOn,
	/// That same timeout in minutes. While it is off, a value set here is kept
	/// aside and stored when it is turned on.
	TimeoutMinutes,
}

fn conv(key: Key) -> Conv {
	match key {
		Key::ScreenOff | Key::Screensaver => Conv::TimeoutOn,
		Key::ScreenOffAfter | Key::ScreensaverAfter => Conv::TimeoutMinutes,
		Key::MouseScrollSpeed | Key::TouchpadScrollSpeed | Key::MouseSpeed | Key::TouchpadSpeed => Conv::Percent,
		Key::None
		| Key::IdleFullscreen
		| Key::RepeatDelay
		| Key::RepeatRate
		| Key::XkbLayout
		| Key::XkbVariant
		| Key::XkbOptions
		| Key::NumLock
		| Key::MouseAccel
		| Key::MouseNatural
		| Key::MiddleEmulation
		| Key::LeftHanded
		| Key::TapToClick
		| Key::TouchpadAccel
		| Key::ClickMethod
		| Key::ScrollMethod
		| Key::TouchpadNatural
		| Key::OffWhileTyping
		| Key::OffWithMouse => Conv::Plain,
	}
}

fn parse_bool(text: &str) -> Option<bool> {
	match text.trim().to_ascii_lowercase().as_str() {
		"true" | "1" | "yes" | "on" => Some(true),
		"false" | "0" | "no" | "off" => Some(false),
		_ => None,
	}
}

fn parse_num(text: &str) -> Option<f64> {
	text.trim().parse::<f64>().ok().filter(|v| v.is_finite())
}

// A whole number is written without a fraction, since Wayfire reads an int
// option as an int.
fn format_num(value: f64) -> String {
	if value.fract() == 0.0 && value.abs() < 1e15 {
		format!("{}", value as i64)
	} else {
		format!("{value}")
	}
}

// Percent to fraction and back. Rounding the percent is the only loss, and the
// trip back from a whole percent is exact, so a reverted row shows its own
// default rather than a hair off it.
fn to_percent(fraction: f64) -> f64 {
	(fraction * 100.0).round()
}

fn from_percent(percent: f64) -> f64 {
	percent / 100.0
}

pub struct Settings {
	ui: &'static Ui,
	wayfire: Wayfire,
	/// Minutes set while their timeout is off, for when it is turned on.
	aside: HashMap<Key, f64>,
	/// The value each touched option had before the first change, for Cancel.
	baseline: Vec<(Setting, Option<String>)>,
	/// Changes not yet in the file, because the last write was refused.
	pending: Vec<(Setting, Option<String>)>,
}

impl Settings {
	pub fn new(ui: &'static Ui, wayfire: Wayfire) -> Settings {
		Settings {
			ui,
			wayfire,
			aside: HashMap::new(),
			baseline: Vec::new(),
			pending: Vec::new(),
		}
	}

	fn row(&self, key: Key) -> &'static Row {
		self.ui.row(key)
	}

	fn setting(&self, key: Key) -> &'static Setting {
		self.row(key)
			.setting
			.as_ref()
			.unwrap_or_else(|| panic!("{} has no setting", key.name()))
	}

	fn stored(&mut self, key: Key) -> Option<String> {
		let s = self.setting(key);
		if let Some((_, value)) = self.pending.iter().find(|(p, _)| p == s) {
			return value.clone().or_else(|| self.wayfire.default_of(&s.section, &s.option));
		}
		self.wayfire.get(&s.section, &s.option)
	}

	fn stored_default(&mut self, key: Key) -> Option<String> {
		let s = self.setting(key);
		self.wayfire.default_of(&s.section, &s.option)
	}

	// The minutes row that shares a timeout with this switch, or the other way.
	fn partner(&self, key: Key) -> Key {
		let setting = self.setting(key);
		self.ui
			.rows
			.iter()
			.find(|r| r.key != key && r.setting.as_ref() == Some(setting))
			.map_or_else(
				|| panic!("{} shares its timeout with no other row", key.name()),
				|r| r.key,
			)
	}

	fn timeout_on(stored: Option<&str>) -> bool {
		stored.and_then(parse_num).is_some_and(|v| v > 0.0)
	}

	// How a stored text reads on a row, before any conversion.
	fn read(&self, key: Key, text: Option<&str>) -> Option<Value> {
		let text = text?;
		match self.row(key).kind {
			Kind::Toggle => parse_bool(text).map(Value::Bool),
			Kind::Slider { .. } => parse_num(text).map(Value::Num),
			Kind::Text | Kind::Dropdown { .. } | Kind::Heading => Some(Value::Text(text.to_string())),
		}
	}

	fn shown(&mut self, key: Key, stored: Option<&str>, default: bool) -> Option<Value> {
		match conv(key) {
			Conv::Plain => self.read(key, stored),
			Conv::Percent => match self.read(key, stored)? {
				Value::Num(v) => Some(Value::Num(to_percent(v))),
				other => Some(other),
			},
			Conv::TimeoutOn => Some(Value::Bool(Self::timeout_on(stored))),
			Conv::TimeoutMinutes => {
				// While off: the minutes set aside, else those of the default
				// if it is on, else the row's own.
				let minutes = |text: Option<&str>| {
					text.and_then(parse_num)
						.filter(|v| *v > 0.0)
						.map(|seconds| Value::Num((seconds / 60.0).round().max(1.0)))
				};
				if let Some(shown) = minutes(stored) {
					return Some(shown);
				}
				if !default && let Some(set_aside) = self.aside.get(&key) {
					return Some(Value::Num(*set_aside));
				}
				let stored_default = self.stored_default(key);
				minutes(stored_default.as_deref()).or_else(|| self.row(key).default.map(Value::Num))
			}
		}
	}

	/// What the row shows now.
	pub fn value(&mut self, key: Key) -> Option<Value> {
		let stored = self.stored(key);
		self.shown(key, stored.as_deref(), false)
	}

	/// What the row shows at its default, if the default is known.
	pub fn default_value(&mut self, key: Key) -> Option<Value> {
		let stored = self.stored_default(key);
		self.shown(key, stored.as_deref(), true)
	}

	pub fn is_default(&mut self, key: Key) -> bool {
		match self.default_value(key) {
			None => true,
			Some(d) => self.value(key) == Some(d),
		}
	}

	/// Why the row cannot act now, or `None` if it can.
	pub fn unavailable(&mut self, key: Key) -> Option<String> {
		let needs = &self.row(key).plugins;
		if needs.is_empty() {
			return None;
		}
		let loaded = self.wayfire.plugins();
		let missing: Vec<&str> = needs
			.iter()
			.filter(|p| !loaded.contains(p))
			.map(String::as_str)
			.collect();
		match missing.as_slice() {
			[] => None,
			[one] => Some(format!("Wayfire's {one} plugin is not loaded.")),
			many => Some(format!("Wayfire's {} plugins are not loaded.", many.join(" and "))),
		}
	}

	pub fn set(&mut self, key: Key, value: Value) -> Result<(), SaveError> {
		let stored = match (conv(key), &self.row(key).kind, value) {
			(Conv::TimeoutOn, _, Value::Bool(on)) => {
				let partner = self.partner(key);
				if on == Self::timeout_on(self.stored(key).as_deref()) {
					return Ok(());
				}
				if on {
					let minutes = match self.value(partner) {
						Some(Value::Num(m)) => m,
						_ => 10.0,
					};
					self.aside.remove(&partner);
					Some(format_num(minutes * 60.0))
				} else {
					if let Some(Value::Num(m)) = self.value(partner) {
						self.aside.insert(partner, m);
					}
					Some("-1".to_string())
				}
			}
			(Conv::TimeoutMinutes, _, Value::Num(minutes)) => {
				let minutes = minutes.round().max(1.0);
				if !Self::timeout_on(self.stored(key).as_deref()) {
					self.aside.insert(key, minutes);
					return Ok(());
				}
				Some(format_num(minutes * 60.0))
			}
			(Conv::Percent, _, Value::Num(percent)) => Some(format_num(from_percent(percent.round()))),
			(Conv::Plain, Kind::Toggle, Value::Bool(b)) => Some(b.to_string()),
			(Conv::Plain, Kind::Slider { .. }, Value::Num(n)) => Some(format_num(n.round())),
			(Conv::Plain, Kind::Dropdown { values, .. }, Value::Text(t)) if values.contains(&t) => Some(t),
			(Conv::Plain, Kind::Text, Value::Text(t)) => Some(t.trim().to_string()),
			(_, _, other) => return Err(SaveError(format!("{}: cannot take {other:?}", key.name()))),
		};
		self.store(key, stored)
	}

	/// Back to the default. An option with no default of the admin's or the
	/// release's is dropped from the file, so Wayfire's own default applies
	/// and later changes to it are not masked.
	pub fn revert(&mut self, key: Key) -> Result<(), SaveError> {
		match conv(key) {
			Conv::Plain | Conv::Percent => {
				let s = self.setting(key);
				let system = self.wayfire.system_value(&s.section, &s.option);
				self.store(key, system)
			}
			Conv::TimeoutOn | Conv::TimeoutMinutes => match self.default_value(key) {
				Some(value) => {
					self.aside.remove(&key);
					self.set(key, value)
				}
				None => Ok(()),
			},
		}
	}

	fn store(&mut self, key: Key, value: Option<String>) -> Result<(), SaveError> {
		let s = self.setting(key).clone();
		if !self.baseline.iter().any(|(b, _)| *b == s) {
			let before = self.wayfire.user_value(&s.section, &s.option);
			self.baseline.push((s.clone(), before));
		}
		self.pending.retain(|(p, _)| *p != s);
		self.pending.push((s, value));
		self.flush()
	}

	fn flush(&mut self) -> Result<(), SaveError> {
		if self.pending.is_empty() {
			return Ok(());
		}
		let changes: Vec<(String, String, Option<String>)> = self
			.pending
			.iter()
			.map(|(s, v)| (s.section.clone(), s.option.clone(), v.clone()))
			.collect();
		self.wayfire.write(&changes)?;
		self.pending.clear();
		Ok(())
	}

	/// Keeps what was changed. Any change a refused write held back is tried
	/// again first.
	pub fn apply(&mut self) -> Result<(), SaveError> {
		self.flush()?;
		self.baseline.clear();
		Ok(())
	}

	/// Puts back every option changed since the last Apply.
	pub fn cancel(&mut self) -> Result<(), SaveError> {
		self.pending = std::mem::take(&mut self.baseline);
		self.aside.clear();
		self.flush()
	}
}

#[cfg(test)]
mod tests {
	use super::{Settings, Value};
	use crate::ui::{Key, Kind, ui};
	use crate::wayfire::{Wayfire, tests::Scratch};

	const USER: &str = "\
# my settings
[core]
plugins = idle cube

[input]
kb_repeat_delay = 300
mouse_cursor_speed = 0.25

[idle]
dpms_timeout = 600
screensaver_timeout = -1
";

	fn open(s: &Scratch) -> Settings {
		Settings::new(ui(), Wayfire::open(&s.xdg()))
	}

	#[test]
	fn values_show_converted() {
		let s = Scratch::new("convert", Some(USER), None);
		let mut st = open(&s);
		assert_eq!(st.value(Key::RepeatDelay), Some(Value::Num(300.0)));
		assert_eq!(st.value(Key::MouseSpeed), Some(Value::Num(25.0)));
		assert_eq!(st.value(Key::ScreenOff), Some(Value::Bool(true)));
		assert_eq!(st.value(Key::ScreenOffAfter), Some(Value::Num(10.0)));
		assert_eq!(st.value(Key::Screensaver), Some(Value::Bool(false)));
		// off, and no minutes of its own: the metadata default of 3600 s
		assert_eq!(st.value(Key::ScreensaverAfter), Some(Value::Num(60.0)));
		assert_eq!(st.value(Key::MouseAccel), Some(Value::Text("default".into())));
		assert_eq!(st.value(Key::TapToClick), Some(Value::Bool(true)));
	}

	#[test]
	fn a_timeout_turned_off_keeps_its_minutes_for_when_it_comes_back_on() {
		let s = Scratch::new("timeout", Some(USER), None);
		let mut st = open(&s);
		st.set(Key::ScreenOff, Value::Bool(false)).unwrap();
		assert!(s.user_file().contains("dpms_timeout = -1"));
		assert_eq!(st.value(Key::ScreenOffAfter), Some(Value::Num(10.0)));
		st.set(Key::ScreenOffAfter, Value::Num(25.0)).unwrap();
		assert!(
			s.user_file().contains("dpms_timeout = -1"),
			"the minutes wait while it is off"
		);
		st.set(Key::ScreenOff, Value::Bool(true)).unwrap();
		assert!(s.user_file().contains("dpms_timeout = 1500"));
		st.set(Key::ScreenOffAfter, Value::Num(5.0)).unwrap();
		assert!(s.user_file().contains("dpms_timeout = 300"));
	}

	#[test]
	fn cancel_puts_back_exactly_what_was_there() {
		let s = Scratch::new("cancel", Some(USER), None);
		let mut st = open(&s);
		st.set(Key::RepeatDelay, Value::Num(650.0)).unwrap();
		st.set(Key::RepeatDelay, Value::Num(700.0)).unwrap();
		st.set(Key::XkbLayout, Value::Text("de".into())).unwrap();
		st.set(Key::ScreenOff, Value::Bool(false)).unwrap();
		assert_ne!(s.user_file(), USER);
		st.cancel().unwrap();
		assert_eq!(s.user_file(), USER);
	}

	#[test]
	fn apply_keeps_changes_and_a_later_cancel_only_undoes_what_came_after() {
		let s = Scratch::new("apply", Some(USER), None);
		let mut st = open(&s);
		st.set(Key::RepeatDelay, Value::Num(650.0)).unwrap();
		st.apply().unwrap();
		st.set(Key::RepeatDelay, Value::Num(200.0)).unwrap();
		st.set(Key::RepeatRate, Value::Num(30.0)).unwrap();
		st.cancel().unwrap();
		assert_eq!(
			s.user_file(),
			USER.replace("kb_repeat_delay = 300", "kb_repeat_delay = 650")
		);
	}

	#[test]
	fn revert_drops_the_option_unless_the_admin_set_a_default() {
		let s = Scratch::new("revert", Some(USER), Some("[input]\nmouse_cursor_speed = -0.5\n"));
		let mut st = open(&s);
		assert!(!st.is_default(Key::RepeatDelay));
		st.revert(Key::RepeatDelay).unwrap();
		assert!(!s.user_file().contains("kb_repeat_delay"));
		assert!(st.is_default(Key::RepeatDelay));
		assert_eq!(st.value(Key::RepeatDelay), Some(Value::Num(400.0)));
		assert_eq!(st.default_value(Key::MouseSpeed), Some(Value::Num(-50.0)));
		st.revert(Key::MouseSpeed).unwrap();
		assert!(s.user_file().contains("mouse_cursor_speed = -0.5"));
		assert!(st.is_default(Key::MouseSpeed));
	}

	#[test]
	fn a_row_needing_a_plugin_that_is_not_loaded_says_so() {
		let s = Scratch::new("plugins", Some("[core]\nplugins = idle\n"), None);
		let mut st = open(&s);
		assert_eq!(st.unavailable(Key::ScreenOff), None);
		assert_eq!(
			st.unavailable(Key::Screensaver).as_deref(),
			Some("Wayfire's cube plugin is not loaded.")
		);
		assert_eq!(st.unavailable(Key::RepeatDelay), None);
	}

	#[test]
	fn a_refused_write_is_held_and_tried_again_on_apply() {
		let s = Scratch::new("held", Some("[input]\nbad line\n"), None);
		let mut st = open(&s);
		assert!(st.set(Key::RepeatDelay, Value::Num(500.0)).is_err());
		assert_eq!(
			st.value(Key::RepeatDelay),
			Some(Value::Num(500.0)),
			"the session still shows it"
		);
		assert!(st.apply().is_err());
		std::fs::write(s.user_path(), "[input]\n").unwrap();
		st.apply().unwrap();
		assert_eq!(s.user_file(), "[input]\nkb_repeat_delay = 500\n");
	}

	// Every row, through a save and a fresh start. A row whose value is never
	// written would change the session and be gone at the next login, with
	// nothing to say so.
	#[test]
	fn every_row_survives_a_save_and_a_relaunch() {
		let s = Scratch::new("relaunch", Some(USER), None);
		let mut st = open(&s);
		let mut wanted = Vec::new();
		for row in ui().rows.iter().filter(|r| r.key != Key::None) {
			let current = st.value(row.key);
			let value = match &row.kind {
				// a timeout's switch ends on, so its minutes are written too
				Kind::Toggle if matches!(row.key, Key::ScreenOff | Key::Screensaver) => Value::Bool(true),
				Kind::Toggle => Value::Bool(current != Some(Value::Bool(true))),
				Kind::Slider { min, max, .. } => {
					let mid = ((min + max) / 2.0).round();
					Value::Num(if current == Some(Value::Num(mid)) {
						mid + 1.0
					} else {
						mid
					})
				}
				Kind::Dropdown { values, .. } => Value::Text(
					values
						.iter()
						.find(|v| Some(Value::Text((*v).clone())) != current)
						.unwrap()
						.clone(),
				),
				Kind::Text => Value::Text(format!("x{}", row.key.name().to_lowercase())),
				Kind::Heading => unreachable!(),
			};
			st.set(row.key, value.clone()).unwrap();
			wanted.push((row.key, value));
		}
		st.apply().unwrap();
		let mut again = open(&s);
		for (key, value) in wanted {
			assert_eq!(again.value(key), Some(value), "{} did not survive", key.name());
		}
	}
}
