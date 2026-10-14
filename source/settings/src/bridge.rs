// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! The one object the QML side talks to. Rows are named by their key, and
//! values cross as plain variants: a bool, a number, a string, or for a
//! dropdown the index of its option.

#[cxx_qt::bridge]
pub mod qobject {
	unsafe extern "C++" {
		include!("cxx-qt-lib/qstring.h");
		type QString = cxx_qt_lib::QString;
		include!("cxx-qt-lib/qvariant.h");
		type QVariant = cxx_qt_lib::QVariant;
	}

	extern "RustQt" {
		#[qobject]
		#[qml_element]
		#[qproperty(QString, error)]
		#[qproperty(i32, revision)]
		type Backend = super::BackendRust;

		/// The declarations, as JSON.
		#[qinvokable]
		fn declarations(self: &Backend) -> QString;

		/// The tab to open on, from `--tab`, or empty.
		#[qinvokable]
		#[cxx_name = "startTab"]
		fn start_tab(self: &Backend) -> QString;

		#[qinvokable]
		fn value(self: Pin<&mut Backend>, name: &QString) -> QVariant;

		#[qinvokable]
		#[cxx_name = "isDefault"]
		fn is_default(self: Pin<&mut Backend>, name: &QString) -> bool;

		/// Why the row is grayed out, or empty.
		#[qinvokable]
		fn unavailable(self: Pin<&mut Backend>, name: &QString) -> QString;

		#[qinvokable]
		#[cxx_name = "setValue"]
		fn set_value(self: Pin<&mut Backend>, name: &QString, value: &QVariant) -> bool;

		#[qinvokable]
		fn revert(self: Pin<&mut Backend>, name: &QString) -> bool;

		#[qinvokable]
		fn apply(self: Pin<&mut Backend>) -> bool;

		#[qinvokable]
		fn cancel(self: Pin<&mut Backend>) -> bool;
	}
}

use crate::settings::{Settings, Value};
use crate::ui::{Key, Kind, ui};
use crate::wayfire::{SaveError, Wayfire, Xdg};
use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QString, QVariant};
use std::sync::OnceLock;

static START_TAB: OnceLock<String> = OnceLock::new();

pub fn set_start_tab(path: String) {
	let _ = START_TAB.set(path);
}

pub struct BackendRust {
	settings: Settings,
	error: QString,
	revision: i32,
}

impl Default for BackendRust {
	fn default() -> Self {
		BackendRust {
			settings: Settings::new(ui(), Wayfire::open(&Xdg::from_env())),
			error: QString::default(),
			revision: 0,
		}
	}
}

fn key_of(name: &QString) -> Key {
	Key::parse(&name.to_string()).unwrap_or(Key::None)
}

fn dropdown_values(key: Key) -> &'static [String] {
	match &ui().row(key).kind {
		Kind::Dropdown { values, .. } => values,
		_ => &[],
	}
}

// Invokables take self whether they need it or not.
#[allow(clippy::unused_self)]
impl qobject::Backend {
	fn declarations(&self) -> QString {
		QString::from(&ui().to_json())
	}

	fn start_tab(&self) -> QString {
		QString::from(START_TAB.get().map_or("", String::as_str))
	}

	fn value(self: Pin<&mut Self>, name: &QString) -> QVariant {
		let key = key_of(name);
		if key == Key::None {
			return QVariant::default();
		}
		match self.rust_mut().settings.value(key) {
			Some(Value::Bool(b)) => QVariant::from(&b),
			Some(Value::Num(n)) => QVariant::from(&n),
			Some(Value::Text(t)) if !dropdown_values(key).is_empty() => {
				let index = dropdown_values(key)
					.iter()
					.position(|v| *v == t)
					.map_or(-1, |i| i as i32);
				QVariant::from(&index)
			}
			Some(Value::Text(t)) => QVariant::from(&QString::from(&t)),
			None => QVariant::default(),
		}
	}

	fn is_default(self: Pin<&mut Self>, name: &QString) -> bool {
		let key = key_of(name);
		key == Key::None || self.rust_mut().settings.is_default(key)
	}

	fn unavailable(self: Pin<&mut Self>, name: &QString) -> QString {
		let key = key_of(name);
		if key == Key::None {
			return QString::default();
		}
		QString::from(&self.rust_mut().settings.unavailable(key).unwrap_or_default())
	}

	fn set_value(self: Pin<&mut Self>, name: &QString, value: &QVariant) -> bool {
		let key = key_of(name);
		if key == Key::None {
			return false;
		}
		let value = match &ui().row(key).kind {
			Kind::Toggle => value.value::<bool>().map(Value::Bool),
			Kind::Slider { .. } => value.value::<f64>().map(Value::Num),
			Kind::Dropdown { values, .. } => value
				.value::<f64>()
				.and_then(|i| values.get(i as usize))
				.map(|v| Value::Text(v.clone())),
			Kind::Text => value.value::<QString>().map(|s| Value::Text(s.to_string())),
			Kind::Heading => None,
		};
		let Some(value) = value else {
			return false;
		};
		self.finish(|s| s.set(key, value))
	}

	fn revert(self: Pin<&mut Self>, name: &QString) -> bool {
		let key = key_of(name);
		key != Key::None && self.finish(|s| s.revert(key))
	}

	fn apply(self: Pin<&mut Self>) -> bool {
		self.finish(Settings::apply)
	}

	fn cancel(self: Pin<&mut Self>) -> bool {
		self.finish(Settings::cancel)
	}

	// Runs a change, then tells the QML side to read every row again, since
	// one change can move others, such as a timeout and its switch.
	fn finish(mut self: Pin<&mut Self>, change: impl FnOnce(&mut Settings) -> Result<(), SaveError>) -> bool {
		let result = change(&mut self.as_mut().rust_mut().settings);
		let error = match &result {
			Ok(()) => QString::default(),
			Err(SaveError(text)) => QString::from(text),
		};
		self.as_mut().set_error(error);
		let next = self.revision().wrapping_add(1);
		self.as_mut().set_revision(next);
		result.is_ok()
	}
}
