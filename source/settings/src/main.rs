// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

//! The settings app: one app for the desktop's settings.

mod application;
mod bridge;
mod idle;
mod ini;
mod settings;
mod ui;
mod wayfire;

use cxx_qt_lib::{QQmlApplicationEngine, QQuickStyle, QString, QUrl};
use std::path::Path;

const USAGE: &str = "\
Usage: lxqtukz-settings [--tab TAB]

  --tab TAB      open on this tab, such as Keyboard or \"Mouse and touchpad/Touchpad\"
  --version      print the version and exit
  -h, --help     print this and exit
";

fn main() {
	let mut args = std::env::args().skip(1);
	while let Some(arg) = args.next() {
		match arg.as_str() {
			"--tab" => match args.next() {
				Some(tab) => bridge::set_start_tab(tab),
				None => fail("--tab needs a tab"),
			},
			"--version" => {
				println!("lxqtukz-settings {}", env!("CARGO_PKG_VERSION"));
				return;
			}
			"-h" | "--help" => {
				print!("{USAGE}");
				return;
			}
			other => fail(&format!("unknown argument: {other}")),
		}
	}

	let mut app = application::ffi::new_application();
	let mut engine = QQmlApplicationEngine::new();

	// The KDE desktop style draws Qt Quick controls through the Qt widget
	// style, so the app follows the same theme as every other Qt app. Fusion
	// stands in where it is not installed. QT_QUICK_CONTROLS_STYLE still wins.
	if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
		let desktop = engine.as_ref().is_some_and(|e| {
			let paths: cxx_qt_lib::QList<QString> = (&e.import_path_list()).into();
			paths
				.iter()
				.any(|p| Path::new(&p.to_string()).join("org/kde/desktop/qmldir").is_file())
		});
		QQuickStyle::set_style(&QString::from(if desktop { "org.kde.desktop" } else { "Fusion" }));
	}

	if let Some(engine) = engine.as_mut() {
		engine.load(&QUrl::from("qrc:/qt/qml/org/lxqtukz/settings/qml/Main.qml"));
	}
	let code = app.as_mut().map_or(1, application::ffi::exec_application);
	// The QML objects go first, so the backend can put back a value a test
	// still holds.
	drop(engine);
	std::process::exit(code);
}

fn fail(message: &str) -> ! {
	eprint!("lxqtukz-settings: {message}\n\n{USAGE}");
	std::process::exit(2);
}
