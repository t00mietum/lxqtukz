// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright © 2026 t00mietum (CryptogID: ปʬϝღถɔ4რఠΔթะ9ƾǝu)

#[cxx_qt::bridge]
pub mod ffi {
	unsafe extern "C++" {
		include!("lxqtukz-settings/src/application.h");
		type QApplication;

		#[cxx_name = "newApplication"]
		fn new_application() -> UniquePtr<QApplication>;

		#[cxx_name = "execApplication"]
		fn exec_application(app: Pin<&mut QApplication>) -> i32;
	}
}
