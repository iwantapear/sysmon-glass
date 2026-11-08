using System;
using System.Diagnostics;
using System.Threading;
using System.Collections.Concurrent;
using System.Collections.Generic;
namespace SysMonGlass {
    public sealed class DgxPoller {
        private volatile bool running; private Thread thread; private Process process;
        private volatile ConcurrentDictionary<string,string> values = new ConcurrentDictionary<string,string>();
        private long lastUpdate;
        private string hostAlias = "dgx"; private string user = ""; private int port = 22; private string probe = "~/.sysmon.sh";
        private readonly object lifecycle = new object();
        private volatile string lastError = "";
        public string LastError { get { return lastError; } }
        private void RecordError(string message) { if (!String.IsNullOrEmpty(message)) lastError = message.Length > 512 ? message.Substring(0,512) : message; }
        private static string ReadBoundedLine(System.IO.TextReader reader) {
            var line = new System.Text.StringBuilder(); int c;
            while ((c=reader.Read()) != -1) {
                if(c == '\n') return line.ToString().TrimEnd('\r');
                if(line.Length >= 4096) throw new System.IO.InvalidDataException("Remote output line exceeded 4096 characters.");
                line.Append((char)c);
            }
            return line.Length == 0 ? null : line.ToString();
        }
        public void Configure(string hostAlias, string user, int port, string probe) {
            if (hostAlias == null || hostAlias.Length > 253 || !System.Text.RegularExpressions.Regex.IsMatch(hostAlias, @"\A[A-Za-z0-9\[:][A-Za-z0-9._:\[\]-]*\z")) throw new ArgumentException("Invalid SSH host alias, IP address or hostname.");
            if (user != null && user.Length > 0 && !System.Text.RegularExpressions.Regex.IsMatch(user, @"\A[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}\z")) throw new ArgumentException("Invalid SSH user.");
            if (port < 1 || port > 65535) throw new ArgumentOutOfRangeException("port");
            // Deliberately limited to simple POSIX paths. No shell expansion other than ~/.
            if (probe == null || probe.Length > 1024 || !System.Text.RegularExpressions.Regex.IsMatch(probe, @"\A(?:~/|/|\./)?[A-Za-z0-9_.][A-Za-z0-9_./-]*\z")) throw new ArgumentException("Invalid probe path.");
            lock (lifecycle) {
                if (thread != null && thread.IsAlive) throw new InvalidOperationException("Stop the poller before configuring it.");
                this.hostAlias=hostAlias; this.user=user ?? ""; this.port=port; this.probe=probe;
                values = new ConcurrentDictionary<string,string>(); Interlocked.Exchange(ref lastUpdate, 0);
            }
        }
        public ProcessStartInfo CreateStartInfo() {
            lock (lifecycle) {
                var si = new ProcessStartInfo("ssh");
                si.UseShellExecute = false; si.CreateNoWindow = true; si.RedirectStandardOutput = true; si.RedirectStandardError = true;
                foreach (var option in new[]{"BatchMode=yes", "ConnectTimeout=6", "ServerAliveInterval=15", "ServerAliveCountMax=2", "StrictHostKeyChecking=yes", "ClearAllForwardings=yes", "ForwardAgent=no", "ForwardX11=no", "RequestTTY=no", "PermitLocalCommand=no"}) {
                    si.ArgumentList.Add("-o"); si.ArgumentList.Add(option);
                }
                si.ArgumentList.Add("-T"); si.ArgumentList.Add("-p"); si.ArgumentList.Add(port.ToString(System.Globalization.CultureInfo.InvariantCulture));
                si.ArgumentList.Add("--"); si.ArgumentList.Add(String.IsNullOrEmpty(user) ? hostAlias : user + "@" + hostAlias);
                // The profile validator rejects quotes; this escape is defense in depth
                // against configs written before that check existed.
                var escapedProbe = probe.Replace("'", "'\''");
                var safeProbe = probe.StartsWith("~/", StringComparison.Ordinal) ? "\"$HOME\"/'" + escapedProbe.Substring(2) + "'" : "'" + escapedProbe + "'";
                si.ArgumentList.Add("while true; do sh " + safeProbe + " && echo __END__; sleep 2; done");
                return si;
            }
        }
        public void Start() {
            lock (lifecycle) {
                if (thread != null && thread.IsAlive) return;
                running = true; thread = new Thread(Loop); thread.IsBackground = true; thread.Start();
            }
        }
        private void Loop() {
            while (running) {
                try {
                    var si = CreateStartInfo();
                    lock (lifecycle) {
                        if (!running) break;
                        process = Process.Start(si);
                    }
                    var sshProcess=process;
                    var errorThread=new Thread(() => {
                        try { string errorLine; while((errorLine=ReadBoundedLine(sshProcess.StandardError)) != null) RecordError(errorLine); }
                        catch(Exception ex) { RecordError(ex.Message); }
                    });
                    errorThread.IsBackground=true; errorThread.Start();
                    string line; var frame = new Dictionary<string,string>(); int lines=0;
                    while (running && (line = ReadBoundedLine(process.StandardOutput)) != null) {
                        if(++lines > 256) throw new System.IO.InvalidDataException("Remote frame exceeded 256 lines.");
                        line = line.Trim();
                        if (line == "__END__") { values = new ConcurrentDictionary<string,string>(frame); frame.Clear(); lines=0; Interlocked.Exchange(ref lastUpdate, Environment.TickCount64); continue; }
                        int i = line.IndexOf('='); if (i > 0 && i <= 128 && frame.Count < 256) frame[line.Substring(0,i).Trim()] = line.Substring(i+1).Trim();
                    }
                } catch(Exception ex) { RecordError(ex.Message); } finally {
                    lock(lifecycle) {
                        try { if(process != null) { if(!process.HasExited) process.Kill(true); process.Dispose(); } } catch(Exception ex) { RecordError(ex.Message); }
                        process=null;
                    }
                }
                for (int i=0; i<30 && running; i++) Thread.Sleep(100);
            }
        }
        public string Get(string key) { string v; return values.TryGetValue(key, out v) ? v : ""; }
        public int AgeSec { get { long n = Interlocked.Read(ref lastUpdate); return n == 0 ? -1 : (int)((Environment.TickCount64-n)/1000); } }
        public void Stop() {
            Thread worker;
            lock (lifecycle) {
                running = false; worker = thread;
                try { if (process != null && !process.HasExited) process.Kill(true); } catch (Exception ex) { RecordError(ex.Message); }
            }
            if (worker != null && worker != Thread.CurrentThread && !worker.Join(8000)) throw new TimeoutException("Remote poller did not stop.");
            values = new ConcurrentDictionary<string,string>(); Interlocked.Exchange(ref lastUpdate, 0);
        }
    }
    public sealed class GpuPoller {
        private volatile bool running; private Thread thread; private Process process; private volatile string last = ""; private long lastUpdate;
        private readonly object lifecycle = new object();
        private volatile string lastError = "";
        public string Last { get { return last; } }
        public string LastError { get { return lastError; } }
        private void RecordError(string message) { if (!String.IsNullOrEmpty(message)) lastError=message.Length > 512 ? message.Substring(0,512) : message; }
        public int AgeSec { get { long n = Interlocked.Read(ref lastUpdate); return n == 0 ? -1 : (int)((Environment.TickCount64-n)/1000); } }
        public void Start() {
            lock(lifecycle) {
                if(thread != null && thread.IsAlive) return;
                running=true; thread=new Thread(Loop); thread.IsBackground=true; thread.Start();
            }
        }
        private static string ReadBoundedOutput(System.IO.Stream stream) {
            using(var buffer=new System.IO.MemoryStream()) {
                var chunk=new byte[4096]; int read;
                while((read=stream.Read(chunk,0,chunk.Length)) > 0) {
                    if(buffer.Length+read > 131072) throw new System.IO.InvalidDataException("GPU process output exceeded 128 KiB.");
                    buffer.Write(chunk,0,read);
                }
                return System.Text.Encoding.UTF8.GetString(buffer.ToArray());
            }
        }
        private void KillProcess(Process target) {
            try { if(target != null && !target.HasExited) target.Kill(true); }
            catch(Exception ex) { RecordError(ex.Message); }
        }
        // Kept separate from the polling loop so timeout/output handling can be tested with fake executables.
        private string RunOnce(ProcessStartInfo startInfo, int timeoutMs) {
            startInfo.UseShellExecute=false; startInfo.CreateNoWindow=true;
            startInfo.RedirectStandardOutput=true; startInfo.RedirectStandardError=true;
            Process current;
            lock(lifecycle) { current=Process.Start(startInfo); process=current; }
            var output=System.Threading.Tasks.Task.Run(() => { try { return ReadBoundedOutput(current.StandardOutput.BaseStream); } catch { KillProcess(current); throw; } });
            var errors=System.Threading.Tasks.Task.Run(() => { try { return ReadBoundedOutput(current.StandardError.BaseStream); } catch { KillProcess(current); throw; } });
            try {
                if(!current.WaitForExit(timeoutMs)) { KillProcess(current); throw new TimeoutException("GPU process exceeded its timeout."); }
                if(!System.Threading.Tasks.Task.WaitAll(new System.Threading.Tasks.Task[]{output,errors},2000)) throw new TimeoutException("GPU output readers did not stop.");
                if(!String.IsNullOrWhiteSpace(errors.Result)) RecordError(errors.Result);
                if(current.ExitCode != 0) throw new InvalidOperationException("GPU process exited with code " + current.ExitCode + ". " + errors.Result);
                return output.Result;
            } finally {
                KillProcess(current);
                lock(lifecycle) { if(Object.ReferenceEquals(process,current)) process=null; }
                current.Dispose();
            }
        }
        private void Loop() {
            while(running) {
                try {
                    var si=new ProcessStartInfo("nvidia-smi", "--query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total,fan.speed,clocks.current.graphics --format=csv,noheader,nounits");
                    if(!running) break;
                    var output=RunOnce(si,8000);
                    if(running && !String.IsNullOrWhiteSpace(output)) { last=output; Interlocked.Exchange(ref lastUpdate,Environment.TickCount64); }
                } catch(Exception ex) { RecordError(ex.GetBaseException().Message); }
                for(int i=0;i<20 && running;i++) Thread.Sleep(100);
            }
        }
        public void Stop() {
            Thread worker;
            lock(lifecycle) { running=false; worker=thread; KillProcess(process); }
            if(worker != null && worker != Thread.CurrentThread && !worker.Join(12000)) throw new TimeoutException("GPU poller did not stop.");
            last=""; Interlocked.Exchange(ref lastUpdate,0);
        }
    }
}
