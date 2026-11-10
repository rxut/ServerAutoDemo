// The settings in ServerAutoDemo.ini, section [Settings].
// A named object with perobjectconfig, so the section does not carry the package
// name: every build has its own package name, and the settings stay the same.
class ServerAutoDemoSettings extends Object
	config(ServerAutoDemo)
	perobjectconfig;

var config string DemoPath; // Folder below System, with a trailing slash. The engine creates it.
var config string DemoMask; // Demo file name, see README.md
var config string DemoChar; // Replaces characters that are not safe in file names

defaultproperties {
	DemoPath="Demos/"
	DemoMask="[%Y_%M_%D_%T]_[%C]_%E"
	DemoChar="_"
}
