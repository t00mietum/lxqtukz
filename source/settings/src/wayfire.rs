// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! Wayfire's settings: the user's `wayfire.ini`, and the defaults under it.
//!
//! The file is the one the running Wayfire was started with, from
//! `WAYFIRE_CONFIG_FILE`, so the app works in whichever Wayfire session it is
//! run from. With that unset it is `~/.config/lxqtukz/wayfire.ini`.
//!
//! Wayfire reads one file with no layers. The session seeds the user's copy
//! from the admin's or the release's, so a default here is the value in the
//! first of those found, and past that Wayfire's own default from its plugin
//! metadata. Wayfire reloads the file when it changes, so a write is live.

use crate::ini::Ini;
use std::collections::HashMap;
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

/// The directories to look in, from the environment, so tests can point them
/// at a scratch tree.
#[derive(Clone)]
pub struct Xdg {
	/// `WAYFIRE_CONFIG_FILE`, when set.
	pub wayfire_file: Option<PathBuf>,
	pub config_home: PathBuf,
	pub config_dirs: Vec<PathBuf>,
	pub data_dirs: Vec<PathBuf>,
}

fn split(var: &str, fallback: &str) -> Vec<PathBuf> {
	let value = std::env::var(var).ok().filter(|v| !v.is_empty());
	value
		.as_deref()
		.unwrap_or(fallback)
		.split(':')
		.filter(|p| !p.is_empty())
		.map(PathBuf::from)
		.collect()
}

impl Xdg {
	pub fn from_env() -> Xdg {
		let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
		Xdg {
			wayfire_file: std::env::var_os("WAYFIRE_CONFIG_FILE")
				.filter(|v| !v.is_empty())
				.map(PathBuf::from),
			config_home: std::env::var_os("XDG_CONFIG_HOME")
				.filter(|v| !v.is_empty())
				.map_or_else(|| home.join(".config"), PathBuf::from),
			config_dirs: split("XDG_CONFIG_DIRS", "/etc/xdg"),
			data_dirs: split("XDG_DATA_DIRS", "/usr/local/share:/usr/share"),
		}
	}
}

/// A save that was refused, with why, for an error box.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SaveError(pub String);

pub struct Wayfire {
	path: PathBuf,
	user: Ini,
	system: Option<Ini>,
	data_dirs: Vec<PathBuf>,
	metadata: HashMap<String, HashMap<String, String>>,
}

impl Wayfire {
	pub fn open(xdg: &Xdg) -> Wayfire {
		let path = xdg
			.wayfire_file
			.clone()
			.unwrap_or_else(|| xdg.config_home.join("lxqtukz/wayfire.ini"));
		let read = |p: &Path| fs::read_to_string(p).ok().map(|t| Ini::parse(&t));
		Wayfire {
			user: read(&path).unwrap_or_else(|| Ini::parse("")),
			system: xdg
				.config_dirs
				.iter()
				.find_map(|d| read(&d.join("lxqtukz/wayfire.ini"))),
			path,
			data_dirs: xdg.data_dirs.clone(),
			metadata: HashMap::new(),
		}
	}

	/// The value Wayfire is using: the user's, else the default.
	pub fn get(&mut self, section: &str, option: &str) -> Option<String> {
		self.user
			.get(section, option)
			.or_else(|| self.default_of(section, option))
	}

	/// The value in the user's own file, if it has one.
	pub fn user_value(&self, section: &str, option: &str) -> Option<String> {
		self.user.get(section, option)
	}

	pub fn system_value(&self, section: &str, option: &str) -> Option<String> {
		self.system.as_ref().and_then(|s| s.get(section, option))
	}

	pub fn default_of(&mut self, section: &str, option: &str) -> Option<String> {
		self.system_value(section, option)
			.or_else(|| self.metadata_default(section, option))
	}

	fn metadata_default(&mut self, plugin: &str, option: &str) -> Option<String> {
		if !self.metadata.contains_key(plugin) {
			let file = self
				.data_dirs
				.iter()
				.map(|d| d.join(format!("wayfire/metadata/{plugin}.xml")))
				.find_map(|p| fs::read_to_string(p).ok());
			self.metadata.insert(
				plugin.to_string(),
				file.map(|x| option_defaults(&x)).unwrap_or_default(),
			);
		}
		self.metadata[plugin].get(option).cloned()
	}

	/// The plugins Wayfire loads, from `[core] plugins`.
	pub fn plugins(&mut self) -> Vec<String> {
		self.get("core", "plugins")
			.unwrap_or_default()
			.split_whitespace()
			.map(str::to_string)
			.collect()
	}

	/// Writes a batch of changes, `None` meaning drop the option. The file is
	/// read again first, so a change another program made since is kept unless
	/// it is to one of these same options.
	pub fn write(&mut self, changes: &[(String, String, Option<String>)]) -> Result<(), SaveError> {
		let mut ini = match fs::read_to_string(&self.path) {
			Ok(text) => Ini::parse(&text),
			Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ini::parse(""),
			Err(e) => return Err(SaveError(format!("{} could not be read: {e}", self.path.display()))),
		};
		if let Some(line) = ini.first_unreadable() {
			self.user = ini;
			return Err(SaveError(format!(
				"Line {line} of {} could not be read, so nothing was saved to it. Saving would lose that line.",
				self.path.display()
			)));
		}
		for (section, option, value) in changes {
			match value {
				Some(v) => ini.set(section, option, v),
				None => ini.remove(section, option),
			}
		}
		save(&self.path, &ini.text())
			.map_err(|e| SaveError(format!("{} could not be saved: {e}", self.path.display())))?;
		self.user = ini;
		Ok(())
	}
}

// Through a temporary file and a rename, so Wayfire never reads half a file
// and an interrupted save leaves the old one whole.
fn save(path: &Path, text: &str) -> std::io::Result<()> {
	let dir = path.parent().unwrap_or(Path::new("."));
	fs::create_dir_all(dir)?;
	let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("wayfire.ini");
	let temp = dir.join(format!(".{name}.{}.tmp", std::process::id()));
	let result = (|| {
		let mut file = fs::File::create(&temp)?;
		file.write_all(text.as_bytes())?;
		file.sync_all()?;
		if let Ok(meta) = fs::metadata(path) {
			fs::set_permissions(&temp, meta.permissions())?;
		}
		fs::rename(&temp, path)
	})();
	if result.is_err() {
		let _ = fs::remove_file(&temp);
	}
	result
}

/// `<option name="x">...<default>v</default>` pairs from a plugin's metadata.
/// Reads only what this needs, rather than XML in general.
fn option_defaults(xml: &str) -> HashMap<String, String> {
	let mut out = HashMap::new();
	let mut rest = xml;
	while let Some(start) = rest.find("<option ") {
		rest = &rest[start + 8..];
		let end = rest.find("</option>").unwrap_or(rest.len());
		let body = &rest[..end];
		let name = body
			.find("name=\"")
			.map(|i| &body[i + 6..])
			.and_then(|s| s.find('"').map(|j| &s[..j]));
		let default = body
			.find("<default>")
			.map(|i| &body[i + 9..])
			.and_then(|s| s.find("</default>").map(|j| &s[..j]));
		if let Some(name) = name {
			out.insert(name.to_string(), unescape(default.unwrap_or("").trim()));
		}
		rest = &rest[end..];
	}
	out
}

fn unescape(text: &str) -> String {
	text.replace("&lt;", "<")
		.replace("&gt;", ">")
		.replace("&quot;", "\"")
		.replace("&apos;", "'")
		.replace("&amp;", "&")
}

#[cfg(test)]
pub mod tests {
	use super::{Wayfire, Xdg, option_defaults};
	use std::fs;
	use std::path::{Path, PathBuf};
	use std::sync::OnceLock;
	use std::time::{SystemTime, UNIX_EPOCH};

	pub const IDLE_XML: &str = r#"<?xml version="1.0"?>
<wayfire>
	<plugin name="idle">
		<option name="screensaver_timeout" type="int">
			<_short>Screensaver timeout</_short>
			<default>3600</default>
		</option>
		<option name="dpms_timeout" type="int">
			<default>-1</default>
		</option>
		<option name="disable_on_fullscreen" type="bool">
			<default>true</default>
		</option>
		<option name="toggle" type="activator">
			<default>none</default>
		</option>
	</plugin>
</wayfire>
"#;

	pub const INPUT_XML: &str = r#"<wayfire><plugin name="input">
		<option name="kb_repeat_delay" type="int"><default>400</default></option>
		<option name="kb_repeat_rate" type="int"><default>40</default></option>
		<option name="xkb_layout" type="string"><default>us</default></option>
		<option name="xkb_variant" type="string"><default></default></option>
		<option name="xkb_options" type="string"><default></default></option>
		<option name="kb_numlock_default_state" type="bool"><default>false</default></option>
		<option name="mouse_cursor_speed" type="double"><default>0.0</default></option>
		<option name="mouse_accel_profile" type="string"><default>default</default></option>
		<option name="mouse_scroll_speed" type="double"><default>1.0</default></option>
		<option name="mouse_natural_scroll" type="bool"><default>false</default></option>
		<option name="middle_emulation" type="bool"><default>false</default></option>
		<option name="left_handed_mode" type="bool"><default>false</default></option>
		<option name="tap_to_click" type="bool"><default>true</default></option>
		<option name="touchpad_cursor_speed" type="double"><default>0.0</default></option>
		<option name="touchpad_accel_profile" type="string"><default>default</default></option>
		<option name="click_method" type="string"><default>default</default></option>
		<option name="scroll_method" type="string"><default>default</default></option>
		<option name="natural_scroll" type="bool"><default>false</default></option>
		<option name="touchpad_scroll_speed" type="double"><default>1.0</default></option>
		<option name="disable_touchpad_while_typing" type="bool"><default>false</default></option>
		<option name="disable_touchpad_while_mouse" type="bool"><default>false</default></option>
	</plugin></wayfire>"#;

	/// A scratch tree with Wayfire's metadata and, optionally, the user's file
	/// and an admin's file.
	pub struct Scratch {
		pub root: PathBuf,
	}

	impl Scratch {
		pub fn new(name: &str, user: Option<&str>, system: Option<&str>) -> Scratch {
			let root = run_dir().join(name);
			let meta = root.join("data/wayfire/metadata");
			fs::create_dir_all(&meta).unwrap();
			fs::write(meta.join("idle.xml"), IDLE_XML).unwrap();
			fs::write(meta.join("input.xml"), INPUT_XML).unwrap();
			if let Some(text) = user {
				fs::create_dir_all(root.join("home/lxqtukz")).unwrap();
				fs::write(root.join("home/lxqtukz/wayfire.ini"), text).unwrap();
			}
			if let Some(text) = system {
				fs::create_dir_all(root.join("etc/lxqtukz")).unwrap();
				fs::write(root.join("etc/lxqtukz/wayfire.ini"), text).unwrap();
			}
			Scratch { root }
		}

		pub fn xdg(&self) -> Xdg {
			Xdg {
				wayfire_file: None,
				config_home: self.root.join("home"),
				config_dirs: vec![self.root.join("etc")],
				data_dirs: vec![self.root.join("data")],
			}
		}

		pub fn user_file(&self) -> String {
			fs::read_to_string(self.root.join("home/lxqtukz/wayfire.ini")).unwrap_or_default()
		}

		pub fn user_path(&self) -> PathBuf {
			self.root.join("home/lxqtukz/wayfire.ini")
		}
	}

	impl Drop for Scratch {
		fn drop(&mut self) {
			// Only ever the case folder this made, under this run's folder.
			if self.root.starts_with(run_dir()) && self.root.join("data/wayfire").is_dir() {
				let _ = fs::remove_dir_all(&self.root);
				let _ = fs::remove_dir(run_dir());
			}
		}
	}

	// One folder per test run, named for when it started, with a folder per
	// case under it.
	fn run_dir() -> &'static Path {
		static DIR: OnceLock<PathBuf> = OnceLock::new();
		DIR.get_or_init(|| {
			let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
			let secs = now.as_secs();
			let (days, day_secs) = (secs / 86_400, secs % 86_400);
			// civil date from days since 1970-01-01, after Howard Hinnant
			let z = days as i64 + 719_468;
			let era = z.div_euclid(146_097);
			let doe = z - era * 146_097;
			let leap_days = doe / 1460 - doe / 36_524 + doe / 146_096;
			let yoe = (doe - leap_days) / 365;
			let year_start = 365 * yoe + yoe / 4 - yoe / 100;
			let doy = doe - year_start;
			let mp = (5 * doy + 2) / 153;
			let day = doy - (153 * mp + 2) / 5 + 1;
			let month = if mp < 10 { mp + 3 } else { mp - 9 };
			let year = yoe + era * 400 + i64::from(month <= 2);
			let stamp = format!(
				"{year:04}{month:02}{day:02}-{:02}{:02}{:02}{:02}",
				day_secs / 3600,
				day_secs / 60 % 60,
				day_secs % 60,
				now.subsec_millis() / 10
			);
			std::env::temp_dir().join(format!("test_lxqtukz-settings_{stamp}"))
		})
	}

	#[test]
	fn metadata_defaults_are_read() {
		let d = option_defaults(IDLE_XML);
		assert_eq!(d["screensaver_timeout"], "3600");
		assert_eq!(d["dpms_timeout"], "-1");
		assert_eq!(d["disable_on_fullscreen"], "true");
	}

	#[test]
	fn defaults_come_from_the_admin_file_then_the_metadata() {
		let s = Scratch::new(
			"layers",
			Some("[idle]\ndpms_timeout = 300\n"),
			Some("[idle]\nscreensaver_timeout = 900\n"),
		);
		let mut wf = Wayfire::open(&s.xdg());
		assert_eq!(wf.get("idle", "dpms_timeout").as_deref(), Some("300"));
		assert_eq!(wf.default_of("idle", "dpms_timeout").as_deref(), Some("-1"));
		assert_eq!(wf.default_of("idle", "screensaver_timeout").as_deref(), Some("900"));
		assert_eq!(wf.get("idle", "screensaver_timeout").as_deref(), Some("900"));
		assert_eq!(wf.default_of("nosuchplugin", "x"), None);
	}

	#[test]
	fn a_write_keeps_what_another_program_changed_meanwhile() {
		let s = Scratch::new("reread", Some("[input]\nkb_repeat_delay = 400\n"), None);
		let mut wf = Wayfire::open(&s.xdg());
		fs::write(
			s.user_path(),
			"# added elsewhere\n[input]\nkb_repeat_delay = 400\nxkb_layout = de\n",
		)
		.unwrap();
		wf.write(&[("input".into(), "kb_repeat_delay".into(), Some("250".into()))])
			.unwrap();
		assert_eq!(
			s.user_file(),
			"# added elsewhere\n[input]\nkb_repeat_delay = 250\nxkb_layout = de\n"
		);
	}

	#[test]
	fn a_file_with_an_unreadable_line_is_not_written() {
		let text = "[input]\nkb_repeat_delay = 400\ngarbage here\n";
		let s = Scratch::new("refuse", Some(text), None);
		let mut wf = Wayfire::open(&s.xdg());
		let err = wf
			.write(&[("input".into(), "kb_repeat_delay".into(), Some("250".into()))])
			.unwrap_err();
		assert!(err.0.contains("Line 3"), "{err:?}");
		assert_eq!(s.user_file(), text);
	}

	#[test]
	fn the_running_wayfire_s_file_wins() {
		let s = Scratch::new("session", Some("[input]\nkb_repeat_delay = 400\n"), None);
		let session = s.root.join("session.ini");
		fs::write(&session, "[input]\nkb_repeat_delay = 250\n").unwrap();
		let mut xdg = s.xdg();
		xdg.wayfire_file = Some(session.clone());
		let mut wf = Wayfire::open(&xdg);
		assert_eq!(wf.get("input", "kb_repeat_delay").as_deref(), Some("250"));
		wf.write(&[("input".into(), "kb_repeat_delay".into(), Some("300".into()))])
			.unwrap();
		assert_eq!(
			fs::read_to_string(&session).unwrap(),
			"[input]\nkb_repeat_delay = 300\n"
		);
		assert_eq!(
			s.user_file(),
			"[input]\nkb_repeat_delay = 400\n",
			"the lxqtukz file is left alone"
		);
	}

	#[test]
	fn a_first_write_makes_the_file() {
		let s = Scratch::new("create", None, None);
		let mut wf = Wayfire::open(&s.xdg());
		assert!(!s.user_path().exists());
		wf.write(&[("idle".into(), "dpms_timeout".into(), Some("600".into()))])
			.unwrap();
		assert_eq!(s.user_file(), "[idle]\ndpms_timeout = 600\n");
	}
}
