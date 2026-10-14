// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! The app's declarations, read from `settings_ui.shcl` (compiled in). That file
//! says what the app shows: tabs, rows, order, groups, the setting behind each
//! row and the layout's measurements. `settings.rs` says how each value is read
//! and written.
//!
//! The file is constant, so anything wrong with it is a build mistake. The tests
//! read the same bytes and fail on all of it, including a row that is missing.

use std::fmt::Write as _;
use std::sync::OnceLock;

// Every setting the app can edit. Kept in code so a match over them stops
// compiling when one is added; the test checks the file against `Key::ALL`,
// which is the only way to catch a row that was never declared.
macro_rules! keys {
	($($name:ident),* $(,)?) => {
		#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
		pub enum Key {
			None, // headings
			$($name),*
		}
		impl Key {
			#[cfg(test)]
			pub const ALL: &'static [Key] = &[$(Key::$name),*];
			pub fn name(self) -> &'static str {
				match self {
					Key::None => "none",
					$(Key::$name => stringify!($name)),*
				}
			}
			pub fn parse(text: &str) -> Option<Key> {
				$(if text.eq_ignore_ascii_case(stringify!($name)) {
					return Some(Key::$name);
				})*
				None
			}
		}
	};
}

#[rustfmt::skip]
keys![
	ScreenOff, ScreenOffAfter, Screensaver, ScreensaverAfter, IdleFullscreen,
	RepeatDelay, RepeatRate, XkbLayout, XkbVariant, XkbOptions, NumLock,
	MouseSpeed, MouseAccel, MouseScrollSpeed, MouseNatural, MiddleEmulation, LeftHanded,
	TapToClick, TouchpadSpeed, TouchpadAccel, ClickMethod,
	ScrollMethod, TouchpadNatural, TouchpadScrollSpeed,
	OffWhileTyping, OffWithMouse,
];

pub struct Tab {
	pub path: String,
	pub title: String,
	pub depth: usize,
	/// Has tabs under it, so it has no rows of its own.
	pub parent: bool,
}

pub enum Kind {
	Heading,
	Toggle,
	Slider { min: f64, max: f64, log: bool },
	Dropdown { options: Vec<String>, values: Vec<String> },
	Text,
}

impl Kind {
	fn name(&self) -> &'static str {
		match self {
			Kind::Heading => "heading",
			Kind::Toggle => "toggle",
			Kind::Slider { .. } => "slider",
			Kind::Dropdown { .. } => "dropdown",
			Kind::Text => "text",
		}
	}
}

/// Where a value lives. Only Wayfire's ini so far.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Setting {
	pub section: String,
	pub option: String,
}

pub struct Row {
	pub key: Key,
	pub kind: Kind,
	pub label: String,
	pub tab: usize,
	pub indent: u8,
	pub help: String,
	pub warning: String,
	pub setting: Option<Setting>,
	/// For a row whose store has no default of its own to show.
	pub default: Option<f64>,
	pub plugins: Vec<String>,
}

pub struct Ui {
	pub tabs: Vec<Tab>,
	pub rows: Vec<Row>,
	pub layout: Vec<(String, f64)>,
	pub help: Vec<(String, String)>,
	pub icons: Vec<(String, String)>,
}

impl Ui {
	pub fn row(&self, key: Key) -> &Row {
		self.rows
			.iter()
			.find(|r| r.key == key)
			.unwrap_or_else(|| panic!("no row for {}", key.name()))
	}
}

const SOURCE: &str = include_str!("settings_ui.shcl");

pub fn ui() -> &'static Ui {
	static CELL: OnceLock<Ui> = OnceLock::new();
	CELL.get_or_init(|| match parse(SOURCE) {
		Ok(ui) => ui,
		// Unreachable in a tested build: the tests read these same bytes.
		Err(problems) => panic!("settings_ui.shcl: {}", problems.join("; ")),
	})
}

fn parse_setting(text: &str) -> Option<Setting> {
	let rest = text.strip_prefix("wayfire:")?;
	let (section, option) = rest.split_once('/')?;
	(!section.is_empty() && !option.is_empty()).then(|| Setting {
		section: section.to_string(),
		option: option.to_string(),
	})
}

fn pairs(doc: &shcl::Document, path: &str, problems: &mut Vec<String>) -> Vec<(String, String)> {
	doc.children(path)
		.into_iter()
		.map(|name| {
			let value = doc.get_string(&format!("{path}.{name}")).unwrap_or_else(|status| {
				problems.push(format!("{path}.{name}: {status:?}"));
				String::new()
			});
			(name, value)
		})
		.collect()
}

#[allow(clippy::too_many_lines)] // one straight read of one document
fn parse(text: &str) -> Result<Ui, Vec<String>> {
	let doc = shcl::Document::parse(text);
	let mut problems: Vec<String> = doc
		.diagnostics()
		.iter()
		.filter(|d| d.severity == shcl::Severity::Error)
		.map(|d| format!("line {}: {}", d.line, d.message))
		.collect();

	let paths = doc.get_string_array("tabs").unwrap_or_default();
	if paths.is_empty() {
		problems.push("tabs: none listed".into());
	}
	let mut tabs: Vec<Tab> = Vec::new();
	for path in &paths {
		let parts: Vec<&str> = path.split('/').collect();
		let parent_path = parts[..parts.len() - 1].join("/");
		if parts.len() > 1 && !paths.contains(&parent_path) {
			problems.push(format!("tabs: {path} is under {parent_path}, which is not listed"));
		}
		tabs.push(Tab {
			path: path.clone(),
			title: parts[parts.len() - 1].to_string(),
			depth: parts.len() - 1,
			parent: paths.iter().any(|p| p.starts_with(&format!("{path}/"))),
		});
	}

	let layout: Vec<(String, f64)> = doc
		.children("layout")
		.into_iter()
		.map(|name| {
			let value = doc.get_float(&format!("layout.{name}")).unwrap_or_else(|status| {
				problems.push(format!("layout.{name}: {status:?}"));
				0.0
			});
			(name, value)
		})
		.collect();
	let help = pairs(&doc, "help", &mut problems);
	let icons = pairs(&doc, "icons", &mut problems);

	let mut rows: Vec<Row> = Vec::new();
	let mut tab: Option<usize> = None;
	for name in doc.children("rows") {
		let at = |field: &str| format!("rows.{name}.{field}");
		let text = |field: &str| doc.get_string(&at(field)).unwrap_or_default();
		let list = |field: &str| doc.get_string_array(&at(field)).unwrap_or_default();
		let kind_text = text("kind");
		let key = if kind_text == "heading" {
			Key::None
		} else {
			let Some(key) = Key::parse(&name) else {
				problems.push(format!("rows.{name}: no setting by that name"));
				continue;
			};
			key
		};
		let kind = match kind_text.as_str() {
			"heading" => {
				let path = text("tab");
				match tabs.iter().position(|t| t.path == path) {
					Some(index) if tabs[index].parent => {
						problems.push(format!("rows.{name}: {path} has tabs under it, so no rows"));
					}
					Some(index) => tab = Some(index),
					None => problems.push(format!("rows.{name}: {path} is not one of the tabs")),
				}
				Kind::Heading
			}
			"toggle" => Kind::Toggle,
			"text" => Kind::Text,
			"slider" => {
				let range = doc.get_float_array(&at("range")).unwrap_or_default();
				if range.len() != 2 || range[0] >= range[1] {
					problems.push(format!("rows.{name}: range must be low, high"));
					continue;
				}
				let log = doc.get_bool(&at("log")).unwrap_or(false);
				if log && range[0] <= 0.0 {
					problems.push(format!("rows.{name}: a log track needs a range above 0"));
				}
				Kind::Slider {
					min: range[0],
					max: range[1],
					log,
				}
			}
			"dropdown" => {
				let options = list("options");
				let values = list("values");
				if options.len() < 2 || options.len() != values.len() {
					problems.push(format!("rows.{name}: a dropdown needs options and as many values"));
				}
				Kind::Dropdown { options, values }
			}
			other => {
				problems.push(format!("rows.{name}: unknown kind {other}"));
				continue;
			}
		};
		let Some(tab) = tab else {
			problems.push(format!("rows.{name}: comes before any heading with a tab"));
			continue;
		};
		let setting_text = text("setting");
		let setting = parse_setting(&setting_text);
		if key != Key::None && setting.is_none() {
			problems.push(format!(
				"rows.{name}: setting {setting_text:?} is not wayfire:<section>/<option>"
			));
		}
		rows.push(Row {
			key,
			kind,
			label: text("label"),
			tab,
			indent: doc.get_int(&at("indent")).unwrap_or(0).clamp(0, 4) as u8,
			help: text("help"),
			warning: text("warning"),
			setting,
			default: doc.get_float(&at("default")).ok(),
			plugins: list("plugins"),
		});
	}

	if problems.is_empty() {
		Ok(Ui {
			tabs,
			rows,
			layout,
			help,
			icons,
		})
	} else {
		Err(problems)
	}
}

fn quote(out: &mut String, text: &str) {
	out.push('"');
	for c in text.chars() {
		match c {
			'"' => out.push_str("\\\""),
			'\\' => out.push_str("\\\\"),
			'\n' => out.push_str("\\n"),
			c if (c as u32) < 0x20 => {
				let _ = write!(out, "\\u{:04x}", c as u32);
			}
			c => out.push(c),
		}
	}
	out.push('"');
}

fn quote_all(out: &mut String, items: &[String]) {
	out.push('[');
	for (i, item) in items.iter().enumerate() {
		if i > 0 {
			out.push(',');
		}
		quote(out, item);
	}
	out.push(']');
}

fn object<T>(out: &mut String, items: &[(String, T)], value: impl Fn(&mut String, &T)) {
	out.push('{');
	for (i, (name, v)) in items.iter().enumerate() {
		if i > 0 {
			out.push(',');
		}
		quote(out, name);
		out.push(':');
		value(out, v);
	}
	out.push('}');
}

impl Ui {
	/// Everything the QML side lays out from, as JSON.
	pub fn to_json(&self) -> String {
		let mut out = String::from("{\"tabs\":[");
		for (i, t) in self.tabs.iter().enumerate() {
			if i > 0 {
				out.push(',');
			}
			out.push_str("{\"path\":");
			quote(&mut out, &t.path);
			out.push_str(",\"title\":");
			quote(&mut out, &t.title);
			let _ = write!(out, ",\"depth\":{},\"parent\":{}}}", t.depth, t.parent);
		}
		out.push_str("],\"rows\":[");
		for (i, r) in self.rows.iter().enumerate() {
			if i > 0 {
				out.push(',');
			}
			out.push_str("{\"name\":");
			quote(&mut out, r.key.name());
			out.push_str(",\"kind\":");
			quote(&mut out, r.kind.name());
			out.push_str(",\"label\":");
			quote(&mut out, &r.label);
			out.push_str(",\"help\":");
			quote(&mut out, &r.help);
			out.push_str(",\"warning\":");
			quote(&mut out, &r.warning);
			let _ = write!(out, ",\"tab\":{},\"indent\":{}", r.tab, r.indent);
			match &r.kind {
				Kind::Slider { min, max, log } => {
					let _ = write!(out, ",\"min\":{min},\"max\":{max},\"log\":{log}");
				}
				Kind::Dropdown { options, .. } => {
					out.push_str(",\"options\":");
					quote_all(&mut out, options);
				}
				_ => {}
			}
			out.push('}');
		}
		out.push_str("],\"layout\":");
		object(&mut out, &self.layout, |o, v| {
			let _ = write!(o, "{v}");
		});
		out.push_str(",\"help\":");
		object(&mut out, &self.help, |o, v| quote(o, v));
		out.push_str(",\"icons\":");
		object(&mut out, &self.icons, |o, v| quote(o, v));
		out.push('}');
		out
	}
}

#[cfg(test)]
mod tests {
	use super::{Key, Kind, SOURCE, parse, ui};

	#[test]
	fn the_declarations_are_complete_and_well_formed() {
		let ui = match parse(SOURCE) {
			Ok(ui) => ui,
			Err(problems) => panic!("settings_ui.shcl:\n  {}", problems.join("\n  ")),
		};
		let declared: Vec<Key> = ui.rows.iter().map(|r| r.key).filter(|k| *k != Key::None).collect();
		let missing: Vec<&str> = Key::ALL
			.iter()
			.filter(|k| !declared.contains(k))
			.map(|k| k.name())
			.collect();
		assert!(missing.is_empty(), "no row for: {missing:?}");
		for key in Key::ALL {
			assert_eq!(
				declared.iter().filter(|k| *k == key).count(),
				1,
				"{} is on more than one row",
				key.name()
			);
		}
	}

	#[test]
	fn every_tab_without_tabs_under_it_has_rows() {
		let ui = ui();
		for (index, tab) in ui.tabs.iter().enumerate() {
			let has_rows = ui.rows.iter().any(|r| r.tab == index);
			assert_eq!(has_rows, !tab.parent, "tab {}", tab.path);
		}
		assert!(matches!(ui.rows[0].kind, Kind::Heading));
	}

	// Every number is a floor that content can outgrow, so the only real
	// mistake is a negative or absurd one, or one the QML reads and is missing.
	#[test]
	fn the_layout_numbers_are_there_and_sane() {
		let ui = ui();
		for name in [
			"pad",
			"buttons_gap",
			"tab_width",
			"tab_pad",
			"tab_pad_v",
			"tab_indent",
			"row_height",
			"row_pad",
			"header_pad",
			"header_gap",
			"subgroup_gap",
			"indent",
			"label_width",
			"label_gap",
			"revert_width",
			"control_width",
			"value_width",
			"text_width",
			"button_width",
			"button_gap",
		] {
			let value = ui.layout.iter().find(|(n, _)| n == name).map(|(_, v)| *v);
			assert!(
				value.is_some_and(|v| (0.0..2000.0).contains(&v)),
				"layout.{name} is {value:?}"
			);
		}
		for name in ["cancel", "apply", "ok", "revert"] {
			assert!(ui.help.iter().any(|(n, v)| n == name && !v.is_empty()), "help.{name}");
		}
		for name in ["revert", "warning"] {
			assert!(ui.icons.iter().any(|(n, v)| n == name && !v.is_empty()), "icons.{name}");
		}
	}

	#[test]
	fn a_bad_document_is_reported_rather_than_half_read() {
		let bad = "tabs: [\"Only\"]\nrows:\n\tH:\n\t\tkind: heading\n\t\ttab: Only\n\tNotASetting:\n\t\tkind: toggle\n";
		let Err(problems) = parse(bad) else {
			panic!("a row naming no setting must be reported")
		};
		assert!(problems.iter().any(|p| p.contains("notasetting")), "{problems:?}");
	}

	#[test]
	fn the_json_is_well_formed_enough_to_count() {
		let json = ui().to_json();
		assert!(json.starts_with('{') && json.ends_with('}'));
		assert_eq!(json.matches('{').count(), json.matches('}').count());
		assert_eq!(json.matches("\"name\":").count(), ui().rows.len());
	}
}
