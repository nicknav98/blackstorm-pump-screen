# Sends raw hex payloads to the pump screen as HID output reports and prints whatever comes back.
# usage: hidx.ps1 -Hex (node frame.js POST conn)   - pair it with frame.js to probe commands by hand.
param([string[]]$Hex = @(''), [int]$WaitMs = 1200)
$src = @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class HidXfer {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)] static extern SafeFileHandle CreateFile(string n, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);
    const int RPT = 1025; // report id byte + 1024 payload

    static byte[] Parse(string hex) {
        hex = hex.Replace(" ", "").Replace("-", "");
        byte[] b = new byte[hex.Length / 2];
        for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return b;
    }

    public static void Run(string path, string[] probes, int waitMs) {
        SafeFileHandle h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        if (h.IsInvalid) { Console.WriteLine("open failed " + Marshal.GetLastWin32Error()); return; }
        using (var fs = new FileStream(h, FileAccess.ReadWrite, RPT, true)) {
            byte[] inbuf = new byte[RPT];
            IAsyncResult ar = fs.BeginRead(inbuf, 0, RPT, null, null);
            foreach (string p in probes) {
                byte[] payload = Parse(p);
                byte[] rpt = new byte[RPT];           // rpt[0] = report id 0
                Array.Copy(payload, 0, rpt, 1, Math.Min(payload.Length, 1024));
                Console.WriteLine("OUT [" + (p.Length > 60 ? p.Substring(0, 60) + "..." : (p.Length == 0 ? "all zeros" : p)) + "]");
                try {
                    IAsyncResult w = fs.BeginWrite(rpt, 0, RPT, null, null);
                    if (!w.AsyncWaitHandle.WaitOne(2000)) { Console.WriteLine("  write timed out (device not accepting data)"); return; }
                    fs.EndWrite(w);
                    Console.WriteLine("  write ok");
                } catch (Exception e) { Console.WriteLine("  write error: " + e.Message); continue; }
                DateTime end = DateTime.Now.AddMilliseconds(waitMs);
                int got = 0;
                while (DateTime.Now < end) {
                    if (ar.AsyncWaitHandle.WaitOne(100)) {
                        int n = fs.EndRead(ar); got++;
                        int last = n - 1; while (last > 0 && inbuf[last] == 0) last--;
                        int show = last + 1;
                        Console.WriteLine("     ascii: " + Encoding.ASCII.GetString(inbuf, 0, show).Replace('\0', '.'));
                        inbuf = new byte[RPT];
                        ar = fs.BeginRead(inbuf, 0, RPT, null, null);
                    }
                }
                if (got == 0) Console.WriteLine("  (no reply)");
            }
        }
    }
}
'@
Add-Type -TypeDefinition $src
$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^HID\\VID_1D6B&PID_013B' } | Select-Object -First 1
if (-not $dev) { 'pump HID device not found'; return }
$path = '\\?\' + ($dev.InstanceId -replace '\\', '#').ToLower() + '#{4d1e55b2-f16f-11cf-88cb-001111000030}'
[HidXfer]::Run($path, $Hex, $WaitMs)
