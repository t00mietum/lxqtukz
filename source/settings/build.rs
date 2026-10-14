// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
	CxxQtBuilder::new_qml_module(QmlModule::new("org.lxqtukz.settings").qml_files(["qml/Main.qml"]))
		.files(["src/bridge.rs", "src/application.rs"])
		.cpp_file("src/application.cpp")
		.qt_module("Widgets")
		.qt_module("Quick")
		.build();
	println!("cargo::rerun-if-changed=src/settings_ui.shcl");
}
