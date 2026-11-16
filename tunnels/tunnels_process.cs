// Owns one Windows Job; closing it terminates only this launch and its descendants.
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace InfrastructureTunnels {
    public sealed class Client : IDisposable {
        public Process Process { get; private set; }
        readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
        IntPtr job;
        [StructLayout(LayoutKind.Sequential)] struct Basic {
            public long UserTime, JobTime; public uint Flags;
            public UIntPtr Min, Max; public uint Active; public UIntPtr Affinity;
            public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct Io { public ulong a,b,c,d,e,f; }
        [StructLayout(LayoutKind.Sequential)] struct Extended {
            public Basic Basic; public Io Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attr, string name);
        [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, ref Extended info, uint length);
        [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        public Client(ProcessStartInfo info) {
            job = CreateJobObject(IntPtr.Zero, null);
            var limits = new Extended(); limits.Basic.Flags = 0x2000; // KILL_ON_JOB_CLOSE
            if (job == IntPtr.Zero || !SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(limits))) {
                Dispose(); throw new InvalidOperationException("Cannot create process Job.");
            }
            try {
                Process = new Process(); Process.StartInfo = info;
                Process.OutputDataReceived += Capture; Process.ErrorDataReceived += Capture;
                if (!Process.Start()) throw new InvalidOperationException("Cannot start client.");
                if (!AssignProcessToJobObject(job, Process.Handle)) {
                    Process.Kill(); throw new InvalidOperationException("Cannot own process Job.");
                }
                Process.BeginOutputReadLine(); Process.BeginErrorReadLine();
            } catch { Dispose(); throw; }
        }
        void Capture(object sender, DataReceivedEventArgs e) {
            // Bounded memory even when a client floods stderr.
            if (e.Data != null) { lines.Enqueue(e.Data); if (lines.Count > 2048) { string old; lines.TryDequeue(out old); } }
        }
        public string ReadLine() { string line; return lines.TryDequeue(out line) ? line : null; }
        public void Dispose() {
            if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
            if (Process != null) { Process.Dispose(); Process = null; }
        }
    }
}
