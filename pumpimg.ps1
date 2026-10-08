# Shows an image on the BlackStorm (Byyeetek) pump screen using the CPS realtime protocol.
# usage: pumpimg.ps1 -Image <path to jpg/png/gif; GIFs animate> [-Width 480 -Height 480 -Seconds 10 -Fps 10 -Brightness 80 -Rotate 90]
#        omit -Image to show a generated test card. -Seconds 0 runs until stopped.
param([string]$Image = '', [int]$Width = 480, [int]$Height = 480, [int]$Seconds = 10, [int]$Fps = 10, [int]$Brightness = -1, [int]$Quality = 80, [ValidateSet(0, 90, 180, 270)][int]$Rotate = 0)   # Rotate = degrees anticlockwise

Add-Type -AssemblyName System.Drawing
$src = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class PumpScreen {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)] static extern SafeFileHandle CreateFile(string n, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr t);
    const int RPT = 1025;   // report id byte + 1024 payload
    const int BLOCK = 1000; // jpeg bytes per report
    static int seq = 100;

    static byte[] Frame(string text) {
        byte[] data = Encoding.ASCII.GetBytes(text);
        int len = data.Length + 5;
        var inner = new List<byte>();
        inner.Add((byte)(len >> 8)); inner.Add((byte)(len & 0xFF));
        int sum = (len >> 8) + (len & 0xFF);
        foreach (byte b in data) { inner.Add(b); sum += b; }
        inner.Add((byte)(sum & 0xFF));
        var o = new List<byte>();
        o.Add(0x5A);
        foreach (byte b in inner) {
            if (b == 0x5A) { o.Add(0x5B); o.Add(1); }
            else if (b == 0x5B) { o.Add(0x5B); o.Add(2); }
            else o.Add(b);
        }
        o.Add(0x5A);
        return o.ToArray();
    }

    static byte[] Request(string method, string cmd, string body) {
        string h = "SeqNumber=" + (seq++) + "\r\nDate=" + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + "\r\n";
        if (body != null) h += "ContentType=json\r\nContentLength=" + body.Length + "\r\n";
        return Frame(method + " " + cmd + " 1\r\n" + h + "\r\n" + (body ?? ""));
    }

    static void Send(FileStream fs, byte[] payload) {
        byte[] rpt = new byte[RPT];
        Array.Copy(payload, 0, rpt, 1, payload.Length);
        fs.Write(rpt, 0, RPT);
        fs.Flush();
    }

    static void SendJpeg(FileStream fs, byte[] jpg, byte id) {
        int count = (jpg.Length + BLOCK - 1) / BLOCK;
        for (int i = 0; i < count; i++) {
            int n = Math.Min(BLOCK, jpg.Length - i * BLOCK);
            byte[] p = new byte[3 + 21 + n];
            p[0] = 0x5C; p[1] = (byte)((21 + n) >> 8); p[2] = (byte)((21 + n) & 0xFF);
            p[3] = id; p[4] = (byte)(count >> 8); p[5] = (byte)count; p[6] = (byte)(i >> 8); p[7] = (byte)i; p[8] = 1; // 1 = jpg
            Array.Copy(jpg, i * BLOCK, p, 24, n);
            Send(fs, p);
        }
    }

    static void StartReader(FileStream fs) {
        byte[] buf = new byte[RPT];
        AsyncCallback cb = null;
        cb = ar => {
            try {
                int n = fs.EndRead(ar);
                int last = n - 1; while (last > 0 && buf[last] == 0) last--;
                string s = Encoding.ASCII.GetString(buf, 1, last).Replace("\r\n", " | ");
                Console.WriteLine("  IN: " + s);
                buf = new byte[RPT];
                fs.BeginRead(buf, 0, RPT, cb, null);
            } catch (Exception) { }
        };
        fs.BeginRead(buf, 0, RPT, cb, null);
    }

    public static void Run(string path, byte[][] jpgs, int[] delays, int seconds, int brightness) {
        SafeFileHandle h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        if (h.IsInvalid) { Console.WriteLine("open failed " + Marshal.GetLastWin32Error()); return; }
        using (var fs = new FileStream(h, FileAccess.ReadWrite, RPT, true)) {
            StartReader(fs);
            Send(fs, Request("POST", "conn", null)); Thread.Sleep(400);
            if (brightness >= 0) { Send(fs, Request("POST", "brightness", "{\"value\":" + brightness + "}")); Thread.Sleep(400); }
            Send(fs, Request("POST", "power", "{\"event\":\"resume\"}")); Thread.Sleep(1200);
            Send(fs, Request("POST", "realtimeDisplay", "{\"enable\":true}")); Thread.Sleep(600);
            int frames = 0; byte id = 1;
            DateTime end = seconds > 0 ? DateTime.Now.AddSeconds(seconds) : DateTime.MaxValue;   // 0 = run until stopped
            while (DateTime.Now < end) {
                int k = frames % jpgs.Length;
                DateTime t0 = DateTime.Now;
                SendJpeg(fs, jpgs[k], id);
                id = (byte)(id % 250 + 1); frames++;
                int rest = delays[k] - (int)(DateTime.Now - t0).TotalMilliseconds;
                if (rest > 0) Thread.Sleep(rest);
            }
            Console.WriteLine("sent " + frames + " frames (" + jpgs.Length + " unique)");
            Send(fs, Request("POST", "conn", null)); Thread.Sleep(500);
            Send(fs, Request("POST", "conn", null)); Thread.Sleep(800);
        }
    }
}
'@
Add-Type -TypeDefinition $src

$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$Quality)

# Draws the current frame of $img (or a test card) onto a WxH canvas and returns it as JPEG bytes.
function Render($img) {
    $bmp = New-Object System.Drawing.Bitmap $Width, $Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"; $g.InterpolationMode = "HighQualityBicubic"
    $g.Clear([System.Drawing.Color]::Black)
    if ($img) {
        $scale = [Math]::Max($Width / $img.Width, $Height / $img.Height)   # cover, centred
        $w = $img.Width * $scale; $h = $img.Height * $scale
        $g.DrawImage($img, [single](($Width - $w) / 2), [single](($Height - $h) / 2), [single]$w, [single]$h)
    } else {
        $half = [int]($Width / 2)
        $g.Clear([System.Drawing.Color]::FromArgb(20, 20, 60))
        $g.FillRectangle([System.Drawing.Brushes]::Crimson, 0, 0, $half, [int]($Height / 2))
        $g.FillRectangle([System.Drawing.Brushes]::LimeGreen, $half, 0, $half, [int]($Height / 2))
        $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 4), 4, 4, $Width - 8, $Height - 8)
        $font = New-Object System.Drawing.Font "Segoe UI", ([single]($Height / 12)), ([System.Drawing.FontStyle]::Bold)
        $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = "Center"; $fmt.LineAlignment = "Center"
        $g.DrawString("PUMP SCREEN`n${Width}x${Height}", $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, ([single]($Height / 2)), $Width, ([single]($Height / 2))), $fmt)
    }
    $g.Dispose()
    switch ($Rotate) { 90 { $bmp.RotateFlip("Rotate270FlipNone") } 180 { $bmp.RotateFlip("Rotate180FlipNone") } 270 { $bmp.RotateFlip("Rotate90FlipNone") } }
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, $codec, $ep); $bmp.Dispose()
    , $ms.ToArray()
}

$jpgs = New-Object "System.Collections.Generic.List[byte[]]"
$delays = New-Object "System.Collections.Generic.List[int]"
if ($Image) {
    $srcImg = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Image))
    $dim = New-Object System.Drawing.Imaging.FrameDimension $srcImg.FrameDimensionsList[0]
    $n = $srcImg.GetFrameCount($dim)
    $times = $null
    if ($n -gt 1) { try { $times = $srcImg.GetPropertyItem(0x5100).Value } catch { } }   # GIF frame delays, 1/100 s each
    for ($i = 0; $i -lt $n; $i++) {
        [void]$srcImg.SelectActiveFrame($dim, $i)
        $jpgs.Add((Render $srcImg))
        $d = 1000 / $Fps
        if ($times) { $d = [BitConverter]::ToInt32($times, $i * 4) * 10; if ($d -lt 20) { $d = 100 } }
        $delays.Add([int]$d)
    }
    $srcImg.Dispose()
} else {
    $jpgs.Add((Render $null)); $delays.Add([int](1000 / $Fps))
}

$dev = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^HID\\VID_1D6B&PID_013B' } | Select-Object -First 1
if (-not $dev) { 'pump HID device not found'; return }
$path = '\\?\' + ($dev.InstanceId -replace '\\', '#').ToLower() + '#{4d1e55b2-f16f-11cf-88cb-001111000030}'
"device: $path  frames: $($jpgs.Count)  ${Width}x${Height}  largest jpeg: $(($jpgs | ForEach-Object Length | Measure-Object -Maximum).Maximum) bytes"
[PumpScreen]::Run($path, $jpgs.ToArray(), $delays.ToArray(), $Seconds, $Brightness)
