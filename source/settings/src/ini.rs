// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! Edits an ini file one option at a time, keeping every other line as it was:
//! comments, blank lines, order, spacing and options nobody touched.
//!
//! Written for Wayfire's format: `[section]`, `option = value`, and `#` or `;`
//! comments on their own lines. A value ending in a backslash goes on to the
//! next line.

pub struct Ini {
	lines: Vec<String>,
	ends_with_newline: bool,
}

enum Line<'a> {
	Other,
	Section(&'a str),
	Entry { key: &'a str, value: &'a str },
	Unreadable,
}

fn classify(line: &str) -> Line<'_> {
	let text = line.trim();
	if text.is_empty() || text.starts_with('#') || text.starts_with(';') {
		Line::Other
	} else if let Some(name) = text.strip_prefix('[').and_then(|t| t.strip_suffix(']')) {
		Line::Section(name.trim())
	} else if let Some((key, value)) = text.split_once('=') {
		Line::Entry {
			key: key.trim(),
			value: value.trim(),
		}
	} else {
		Line::Unreadable
	}
}

impl Ini {
	pub fn parse(text: &str) -> Ini {
		Ini {
			lines: text.lines().map(str::to_string).collect(),
			ends_with_newline: text.is_empty() || text.ends_with('\n'),
		}
	}

	// Each line with the section it sits in, skipping the lines that continue a
	// value from the line before.
	fn walk(&self) -> Vec<(usize, Option<&str>, Line<'_>)> {
		let mut out = Vec::with_capacity(self.lines.len());
		let mut section: Option<&str> = None;
		let mut continued = false;
		for (index, line) in self.lines.iter().enumerate() {
			if continued {
				continued = line.trim_end().ends_with('\\');
				continue;
			}
			let kind = classify(line);
			match kind {
				Line::Section(name) => section = Some(name),
				Line::Entry { value, .. } => continued = value.ends_with('\\'),
				_ => {}
			}
			out.push((index, section, kind));
		}
		out
	}

	/// The first line that is none of a comment, a section or an option,
	/// numbered from 1. Saving would lose what it meant, so callers refuse to.
	pub fn first_unreadable(&self) -> Option<usize> {
		self.walk()
			.into_iter()
			.find(|(_, _, kind)| matches!(kind, Line::Unreadable))
			.map(|(index, _, _)| index + 1)
	}

	// Wayfire takes the last of repeated options, so the last one is the one
	// that counts.
	fn find(&self, section: &str, key: &str) -> Option<usize> {
		self.walk()
			.into_iter()
			.filter(|(_, s, kind)| *s == Some(section) && matches!(kind, Line::Entry { key: k, .. } if *k == key))
			.map(|(index, _, _)| index)
			.next_back()
	}

	pub fn get(&self, section: &str, key: &str) -> Option<String> {
		let index = self.find(section, key)?;
		let mut value = match classify(&self.lines[index]) {
			Line::Entry { value, .. } => value.to_string(),
			_ => return None,
		};
		for next in &self.lines[index + 1..self.span_end(index)] {
			value.pop();
			value = format!("{} {}", value.trim_end(), next.trim());
		}
		Some(value)
	}

	// One past the last line of the option starting at `index`.
	fn span_end(&self, index: usize) -> usize {
		let mut end = index + 1;
		while end < self.lines.len() && self.lines[end - 1].trim_end().ends_with('\\') {
			end += 1;
		}
		end
	}

	pub fn set(&mut self, section: &str, key: &str, value: &str) {
		if let Some(index) = self.find(section, key) {
			let end = self.span_end(index);
			self.lines.drain(index + 1..end);
			let line = &self.lines[index];
			let eq = line.find('=').unwrap_or(line.len());
			let gap = if line[eq + 1..].starts_with(char::is_whitespace) {
				" "
			} else {
				""
			};
			self.lines[index] = format!("{}{gap}{value}", &line[..=eq]);
			return;
		}
		let entry = format!("{key} = {value}");
		if let Some(at) = self.section_end(section) {
			self.lines.insert(at, entry);
		} else {
			if self.lines.last().is_some_and(|l| !l.trim().is_empty()) {
				self.lines.push(String::new());
			}
			self.lines.push(format!("[{section}]"));
			self.lines.push(entry);
		}
	}

	/// Drops the option, so Wayfire falls back to its own default.
	pub fn remove(&mut self, section: &str, key: &str) {
		while let Some(index) = self.find(section, key) {
			let end = self.span_end(index);
			self.lines.drain(index..end);
		}
	}

	// One past the last option or section line of the section's last block, so
	// a new option sits with its neighbors rather than after a trailing blank.
	fn section_end(&self, section: &str) -> Option<usize> {
		let mut end = None;
		for (index, s, kind) in self.walk() {
			if s == Some(section) && !matches!(kind, Line::Other) {
				end = Some(index + 1);
			}
		}
		// past any continuation lines of the option found last
		end.map(|at| self.span_end(at - 1))
	}

	pub fn text(&self) -> String {
		let mut text = self.lines.join("\n");
		if self.ends_with_newline && !self.lines.is_empty() {
			text.push('\n');
		}
		text
	}
}

#[cfg(test)]
mod tests {
	use super::Ini;

	const SAMPLE: &str = "\
# Wayfire config
[core]
plugins = idle \\
  cube

[input]
# keyboard
kb_repeat_delay=400
xkb_layout = us

[idle]
dpms_timeout = -1
";

	#[test]
	fn reads_values_including_continued_ones() {
		let ini = Ini::parse(SAMPLE);
		assert_eq!(ini.get("input", "kb_repeat_delay").as_deref(), Some("400"));
		assert_eq!(ini.get("idle", "dpms_timeout").as_deref(), Some("-1"));
		assert_eq!(ini.get("core", "plugins").as_deref(), Some("idle cube"));
		assert_eq!(ini.get("idle", "missing"), None);
		assert_eq!(ini.first_unreadable(), None);
	}

	#[test]
	fn an_edit_changes_only_its_own_line() {
		let mut ini = Ini::parse(SAMPLE);
		ini.set("input", "kb_repeat_delay", "250");
		ini.set("idle", "dpms_timeout", "600");
		let want = SAMPLE
			.replace("kb_repeat_delay=400", "kb_repeat_delay=250")
			.replace("dpms_timeout = -1", "dpms_timeout = 600");
		assert_eq!(ini.text(), want);
	}

	#[test]
	fn a_new_option_joins_its_section_and_a_new_section_goes_last() {
		let mut ini = Ini::parse(SAMPLE);
		ini.set("input", "xkb_options", "caps:escape");
		ini.set("cube", "zoom", "1.5");
		ini.set("core", "xwayland", "true");
		let text = ini.text();
		assert!(
			text.contains("xkb_layout = us\nxkb_options = caps:escape\n\n[idle]"),
			"{text}"
		);
		assert!(text.ends_with("dpms_timeout = -1\n\n[cube]\nzoom = 1.5\n"), "{text}");
		assert!(text.contains("  cube\nxwayland = true\n"), "{text}");
	}

	#[test]
	fn remove_takes_the_option_and_its_continuation() {
		let mut ini = Ini::parse(SAMPLE);
		ini.remove("core", "plugins");
		ini.remove("input", "xkb_layout");
		assert_eq!(
			ini.text(),
			SAMPLE
				.replace("plugins = idle \\\n  cube\n", "")
				.replace("xkb_layout = us\n", "")
		);
	}

	#[test]
	fn setting_a_continued_option_replaces_all_of_it() {
		let mut ini = Ini::parse(SAMPLE);
		ini.set("core", "plugins", "idle");
		assert!(
			ini.text()
				.starts_with("# Wayfire config\n[core]\nplugins = idle\n\n[input]")
		);
	}

	#[test]
	fn the_last_of_repeated_options_counts() {
		let mut ini = Ini::parse("[a]\nx = 1\nx = 2\n");
		assert_eq!(ini.get("a", "x").as_deref(), Some("2"));
		ini.set("a", "x", "3");
		assert_eq!(ini.text(), "[a]\nx = 1\nx = 3\n");
	}

	#[test]
	fn an_unreadable_line_is_found() {
		let ini = Ini::parse("[a]\nx = 1\nthis is not an option\n");
		assert_eq!(ini.first_unreadable(), Some(3));
	}

	#[test]
	fn a_file_with_no_final_newline_keeps_it_that_way() {
		let mut ini = Ini::parse("[a]\nx = 1");
		ini.set("a", "x", "2");
		assert_eq!(ini.text(), "[a]\nx = 2");
	}
}
