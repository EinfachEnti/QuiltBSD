#!/usr/bin/env python3
"""GUI USB writer for QuiltBSD installer images."""
from __future__ import annotations
import json, os, pathlib, subprocess, sys, threading, tkinter as tk
from tkinter import filedialog, messagebox, ttk

ROOT = pathlib.Path(__file__).resolve().parent
CLI = ROOT / 'quiltbsd-usb-installer.py'
PYTHON = sys.executable or 'python3'


def get_devices():
    proc = subprocess.run([PYTHON, str(CLI), '--list-json'], check=True, capture_output=True, text=True)
    return json.loads(proc.stdout)

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('Ubuntu-like-usb-writer')
        self.geometry('760x520')
        self.resizable(True, True)
        self.image_var = tk.StringVar()
        self.device_var = tk.StringVar()
        self.status_var = tk.StringVar(value='Ready')
        self.devices = []
        self._build()
        self.refresh_devices()

    def _build(self):
        frm = ttk.Frame(self, padding=12)
        frm.pack(fill='both', expand=True)
        ttk.Label(frm, text='QuiltBSD image:').grid(row=0, column=0, sticky='w')
        ttk.Entry(frm, textvariable=self.image_var, width=70).grid(row=1, column=0, sticky='ew', padx=(0,8))
        ttk.Button(frm, text='Browse…', command=self.browse_image).grid(row=1, column=1)
        ttk.Label(frm, text='USB target:').grid(row=2, column=0, sticky='w', pady=(12,0))
        self.combo = ttk.Combobox(frm, textvariable=self.device_var, state='readonly', width=70)
        self.combo.grid(row=3, column=0, sticky='ew', padx=(0,8))
        ttk.Button(frm, text='Refresh', command=self.refresh_devices).grid(row=3, column=1)
        ttk.Button(frm, text='Write image', command=self.write_image).grid(row=4, column=0, sticky='w', pady=(12,0))
        ttk.Label(frm, textvariable=self.status_var).grid(row=4, column=1, sticky='e')
        self.output = tk.Text(frm, height=20)
        self.output.grid(row=5, column=0, columnspan=2, sticky='nsew', pady=(12,0))
        frm.columnconfigure(0, weight=1)
        frm.rowconfigure(5, weight=1)

    def browse_image(self):
        path = filedialog.askopenfilename(title='Select QuiltBSD installer image')
        if path:
            self.image_var.set(path)

    def refresh_devices(self):
        try:
            self.devices = get_devices()
        except Exception as exc:
            messagebox.showerror('Ubuntu-like-usb-writer', f'Could not enumerate devices:\n{exc}')
            return
        labels = [f"{d['id']} | {d['label']}" for d in self.devices]
        self.combo['values'] = labels
        if labels:
            self.combo.current(0)

    def log(self, msg):
        self.output.insert('end', msg)
        self.output.see('end')
        self.update_idletasks()

    def write_image(self):
        image = self.image_var.get().strip()
        idx = self.combo.current()
        if not image or not os.path.exists(image):
            messagebox.showerror('Ubuntu-like-usb-writer', 'Please select a valid installer image.')
            return
        if idx < 0 or idx >= len(self.devices):
            messagebox.showerror('Ubuntu-like-usb-writer', 'Please select a USB target device.')
            return
        device = self.devices[idx]['path']
        if not messagebox.askyesno('Ubuntu-like-usb-writer', f'Erase {device} and write\n{image}\n?'):
            return
        self.output.delete('1.0', 'end')
        self.status_var.set('Writing…')
        threading.Thread(target=self._run_write, args=(image, device), daemon=True).start()

    def _run_write(self, image, device):
        try:
            proc = subprocess.Popen([PYTHON, str(CLI), '--yes', image, device], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            assert proc.stdout is not None
            for line in proc.stdout:
                self.log(line)
            code = proc.wait()
            self.status_var.set('Done' if code == 0 else 'Failed')
            if code == 0:
                messagebox.showinfo('Ubuntu-like-usb-writer', 'QuiltBSD installer image was written successfully.')
            else:
                messagebox.showerror('Ubuntu-like-usb-writer', 'Writing the image failed. See the log output.')
        except Exception as exc:
            self.status_var.set('Failed')
            messagebox.showerror('Ubuntu-like-usb-writer', str(exc))

if __name__ == '__main__':
    App().mainloop()
