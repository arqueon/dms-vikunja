import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand(
            "dmsVikunja.dependencies",
            [
                "sh", "-c",
                "command -v python3 >/dev/null && command -v secret-tool >/dev/null && command -v notify-send >/dev/null"
            ],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    done(null)
                    return
                }
                done({
                    "title": "dms-vikunja dependencies are missing",
                    "details": "python3, secret-tool (libsecret), and notify-send (libnotify) are required on PATH. Install them and re-enable the plugin."
                })
            }
        )
    }
}
