import Foundation

// LaunchServices attributes Wi-Fi/location permission to the app, not its launcher.
enum LoginRegistration {
    static let label = "ru.hl100.autoturn.login"
    static let appPath = "/Applications/AutoTurn.app"
    static func arguments() -> [String] { ["/usr/bin/open", "-g", "-a", appPath, "--args", "--background"] }
    static func existing(in directory:URL) -> Bool {
        let file = directory.appendingPathComponent(label + ".plist")
        guard let data = try? Data(contentsOf:file), let plist = (try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],
              plist["Label"] as? String == label, plist["RunAtLoad"] as? Bool == true,
              let args = plist["ProgramArguments"] as? [String] else { return false }
        return args == arguments() || args == [appPath + "/Contents/MacOS/AutoTurn", "--background"]
    }
    static func set(_ enabled:Bool,in directory:URL) throws {
        let file = directory.appendingPathComponent(label + ".plist")
        if enabled {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let plist:[String:Any] = ["Label":label,"ProgramArguments":arguments(),"RunAtLoad":true,"ProcessType":"Interactive"]
            try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:file,options:.atomic)
        } else if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
    }
}
