"""Boundary tests for the native loader; uses tiny synthetic x86-64 images."""
from paths import ROOT
from pathlib import Path
import os
import sys
import struct
import subprocess
import tempfile
import unittest

EXE = Path(os.environ.get('BB_PROBE', ROOT / 'out/bb-probe'))
PAGE = os.sysconf('SC_PAGESIZE') if hasattr(os,'sysconf') else 4096


def package(code, relocs=(), names=(), capabilities=None):
    image = code.ljust(PAGE, b'\0')
    header = struct.pack('<8sQQQQQ', b'BBPROBE1' if capabilities is None else b'BBPROBE2', len(image), 0, 1, len(relocs), len(names))
    if capabilities is not None:
        header += struct.pack('<Q', capabilities)
    segment = struct.pack('<QQQ', 0, len(image), 5)
    return (header + segment + b''.join(n.encode().ljust(128, b'\0') for n in names)
            + b''.join(struct.pack('<QQqq', *r) for r in relocs) + image)


def native_package(name='fixture-native', binding_address=None, binding_kind=1,
                   lib_flags=5, init=b'\x31\xc0\xc3', native=b'\xc3', metadata=None):
    # Main calls an import then tail-jumps to the terminal diagnostic import.
    code = b'\x48\x83\xec\x08\xff\x15\x16\0\0\0\x48\x83\xc4\x08\xff\x25\x14\0\0\0'
    if binding_address is None:
        binding_address = PAGE + 64
    image = code.ljust(PAGE,b'\0') + init.ljust(64,b'\0') + native
    image = image.ljust(3 * PAGE,b'\0')
    header=struct.pack('<8s6Q',b'BBPROBE3',len(image),0,3,2,2,1)
    meta=metadata or (PAGE,2 * PAGE,PAGE,2 * PAGE,32,4,1,256)
    return (header + struct.pack('<8Q',*meta) + struct.pack('<3Q',0,binding_address,binding_kind)
            + struct.pack('<9Q',0,PAGE,5,PAGE,PAGE,lib_flags,2 * PAGE,PAGE,6)
            + name.encode().ljust(128,b'\0') + b'after-native'.ljust(128,b'\0')
            + struct.pack('<8Q',32,1,0,0,40,1,1,0) + image)


def thread_package():
    """A linked guest initializer creates and joins a guest-code worker."""
    image=bytearray(3 * PAGE)
    image[:8]=bytes.fromhex('ff25020000009090')  # jump to terminal import at +8
    init=bytearray()

    def rip(prefix,target):
        here=PAGE + len(init)
        init.extend(prefix)
        init.extend(struct.pack('<i',target - (here + len(prefix) + 4)))

    rip(bytes.fromhex('488d3d'),2 * PAGE)       # rdi = &thread_handle
    init.extend(bytes.fromhex('31f6'))          # rsi = NULL attr
    rip(bytes.fromhex('488d15'),PAGE + 128)     # rdx = worker
    init.extend(bytes.fromhex('31c9'))          # rcx = NULL argument
    rip(bytes.fromhex('4c8d05'),2 * PAGE + 64)  # r8 = name
    rip(bytes.fromhex('ff15'),PAGE + 256)       # scePthreadCreate
    init.extend(bytes.fromhex('85c07500'))      # test eax; jne fail
    first_fail=len(init)-1
    rip(bytes.fromhex('488b3d'),2 * PAGE)       # rdi = thread_handle
    rip(bytes.fromhex('488d35'),2 * PAGE + 8)   # rsi = &result
    rip(bytes.fromhex('ff15'),PAGE + 264)       # scePthreadJoin
    init.extend(bytes.fromhex('85c07500'))
    second_fail=len(init)-1
    rip(bytes.fromhex('488b05'),2 * PAGE + 8)   # rax = result
    init.extend(bytes.fromhex('4885c07500'))    # test rax; jne fail
    third_fail=len(init)-1
    init.extend(bytes.fromhex('31c0c3'))        # success: return 0
    fail=len(init)
    init.extend(bytes.fromhex('b801000000c3'))  # failure: return 1
    for branch in (first_fail,second_fail,third_fail):
        init[branch]=fail - (branch + 1)
    assert len(init)<128
    image[PAGE:PAGE + len(init)]=init

    # The linker rewrites this exact GS load. Check TCB, thread handle and stack.
    worker=bytearray(bytes.fromhex('65488b042500000000483b007500'))
    branches=[len(worker)-1]
    worker.extend(bytes.fromhex('488b401048c1e8284885c07500'))  # tcb[2] >> 40 must be zero
    branches.append(len(worker)-1)
    worker.extend(bytes.fromhex('4889e048c1e828c3'))  # return rsp >> 40
    fail=len(worker)
    worker.extend(bytes.fromhex('b801000000c3'))
    for branch in branches:
        worker[branch]=fail - (branch + 1)
    image[PAGE + 128:PAGE + 128 + len(worker)]=worker
    image[2 * PAGE + 64:2 * PAGE + 71]=b'worker\0'
    names=['6UgtwV+0zb4#p#J','onNY9Byn-W8#p#J','after-thread']
    relocs=[(8,1,2,0),(PAGE + 256,1,0,0),(PAGE + 264,1,1,0)]
    header=struct.pack('<8s6Q',b'BBPROBE3',len(image),0,3,len(relocs),len(names),1)
    meta=struct.pack('<8Q',PAGE,PAGE,PAGE,0,0,0,0,256)
    segments=struct.pack('<9Q',0,PAGE,5,PAGE,PAGE,5,2 * PAGE,PAGE,6)
    return (header + meta + segments +
            b''.join(name.encode().ljust(128,b'\0') for name in names) +
            b''.join(struct.pack('<QQqq',*r) for r in relocs) + image)


@unittest.skipUnless(EXE.exists(), 'build native probe first')
class LoaderTests(unittest.TestCase):
    def test_invalid_content_profile_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'content.bin'
            for data in (b'BBCONT01',struct.pack('<8s5I',b'BBCONT01',2,0,0,0,0),
                         struct.pack('<8s5I',b'BBCONT01',3,0,0,0,0)+b'extra'):
                with self.subTest(data=data):
                    path.write_bytes(data)
                    r=self.run_image(package(b'\xc3'),'--content-profile',str(path))
                    self.assertEqual(r.returncode,1,r.stdout+r.stderr)
                    self.assertIn('content profile',r.stderr)

    def run_image(self, data, *options):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'boot.bin'
            path.write_bytes(data)
            return subprocess.run([str(EXE.resolve()), str(path), '--cpu-only', *options],
                                  capture_output=True, text=True, timeout=5)

    def test_original_instruction_reaches_named_import(self):
        # jmp [rip+2]; two padding bytes; relocated function pointer at +8
        r = self.run_image(package(b'\xff\x25\x02\0\0\0\x90\x90', [(8, 1, 0, 0)], ['fixture-import']))
        self.assertEqual(r.returncode, 20, r.stderr)
        self.assertIn('first unsupported PS4 import: fixture-import', r.stdout)

    def test_native_initializer_and_export_return(self):
        r=self.run_image(native_package())
        self.assertEqual(r.returncode,20,r.stdout+r.stderr)
        self.assertIn('Module 0 initializer returned 0',r.stdout)
        self.assertIn('first unsupported PS4 import: after-native',r.stdout)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS TLS shim test')
    def test_main_guest_tls_load(self):
        # Check TCB, flags, RCX and both halves of YMM0 across the TLS shim.
        code=bytearray(bytes.fromhex('b978563412c5fd76c031d265488b042500000000'))
        branches=[]
        def fail_if_not_equal(check):
            code.extend(check)
            code.extend(bytes.fromhex('7500'))
            branches.append(len(code)-1)
        fail_if_not_equal(b'')                       # ZF from xor edx,edx
        fail_if_not_equal(bytes.fromhex('81f978563412'))  # RCX unchanged
        fail_if_not_equal(bytes.fromhex('483b00'))        # TCB self-pointer
        fail_if_not_equal(bytes.fromhex('c5fdd7c083f8ff'))  # YMM0 all ones
        code.extend(bytes.fromhex('31c0c3'))
        failure=len(code)
        code.extend(bytes.fromhex('b801000000c3'))
        for branch in branches:
            code[branch]=failure - (branch + 1)
        r=self.run_image(native_package(init=code))
        self.assertEqual(r.returncode,20,r.stdout+r.stderr)
        self.assertIn('Guest TCB loads redirected to macOS thread shim: 1',r.stdout)
        self.assertIn('Module 0 initializer returned 0',r.stdout)

    def test_guest_image_is_below_one_terabyte(self):
        # lea rax, [rip]; shr rax, 40; return 0 iff guest code lies below 1 TiB.
        code=bytes.fromhex('488d050000000048c1e828c3')
        r=self.run_image(native_package(init=code))
        self.assertEqual(r.returncode,20,r.stdout+r.stderr)
        self.assertIn('Module 0 initializer returned 0',r.stdout)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS TLS shim test')
    def test_guest_created_thread_tls_and_low_stack(self):
        r=self.run_image(thread_package())
        self.assertEqual(r.returncode,20,r.stdout+r.stderr)
        self.assertIn('Guest TCB loads redirected to macOS thread shim: 1',r.stdout)
        self.assertIn("guest thread 'worker' created",r.stdout)
        self.assertIn('Module 0 initializer returned 0',r.stdout)

    def test_host_contract_takes_priority_over_native_export(self):
        r=self.run_image(native_package(name='bzQExy189ZI#q#q',native=b'\x0f\x0b'))
        self.assertEqual(r.returncode,20,r.stdout+r.stderr)
        self.assertIn('_init_env returned',r.stdout)
        self.assertIn('first unsupported PS4 import: after-native',r.stdout)

    def test_strict_mode_skips_native_initialization_and_binding(self):
        r=self.run_image(native_package(init=b'\x0f\x0b'), '--strict-imports')
        self.assertEqual(r.returncode,20,r.stdout+r.stderr)
        self.assertIn('first unsupported PS4 import: fixture-native',r.stdout)
        self.assertNotIn('Starting native libc',r.stdout)

    def test_native_metadata_and_bindings_are_validated(self):
        for kwargs,message in [
            ({'binding_address':3 * PAGE},'invalid native binding'),
            ({'binding_kind':2},'native export kind/range mismatch'),
            ({'lib_flags':4},'native function is not executable'),
            ({'metadata':(PAGE,2 * PAGE,PAGE,2 * PAGE,32,33,1,256)},'invalid linked module metadata'),
            ({'metadata':(PAGE,2 * PAGE,PAGE,2 * PAGE,32,4,1,3 * PAGE - 8)},'unmapped procparam'),
        ]:
            with self.subTest(kwargs=kwargs):
                r=self.run_image(native_package(**kwargs))
                self.assertEqual(r.returncode,1,r.stdout+r.stderr)
                self.assertIn(message,r.stderr)

    def test_failed_native_initializer_does_not_enter_game(self):
        r=self.run_image(native_package(init=b'\xb8\x01\0\0\0\xc3'))
        self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        self.assertIn('module initializer failed',r.stderr)
        self.assertNotIn('Entering original',r.stdout)

    def test_base_relative_address_is_relocated(self):
        # jump via a relative relocation to code at +16, then to an import at +24
        code = b'\xff\x25\x02\0\0\0\x90\x90' + b'\0'*8 + b'\xff\x25\x02\0\0\0\x90\x90'
        r = self.run_image(package(code, [(8, 0, 16, 0), (24, 1, 0, 0)], ['after-relative-jump']))
        self.assertEqual(r.returncode, 20, r.stderr)
        self.assertIn('after-relative-jump', r.stdout)

    def test_out_of_bounds_relocation_is_rejected(self):
        r = self.run_image(package(b'\xc3', [(PAGE - 4, 0, 0, 0)]))
        self.assertEqual(r.returncode, 1)
        self.assertIn('bad relocation', r.stderr)

    def test_truncated_image_is_rejected(self):
        r = self.run_image(package(b'\xc3')[:-1])
        self.assertEqual(r.returncode, 1)
        self.assertIn('incorrect memory image size', r.stderr)

    def test_illegal_instruction_reports_guest_offset(self):
        r = self.run_image(package(b'\x0f\x0b'))
        self.assertEqual(r.returncode, 132)
        self.assertIn('at guest offset 0x0,', r.stderr)

    def test_runtime_returns_from_verified_init_env(self):
        # Align stack, call _init_env through +32, then tail-jump to unknown +40.
        code = b'\x48\x83\xec\x08\xff\x15\x16\0\0\0\x48\x83\xc4\x08\xff\x25\x14\0\0\0'
        data = package(code, [(32,1,0,0),(40,1,1,0)], ['bzQExy189ZI#q#q','after-init'], 1)
        r = self.run_image(data)
        self.assertEqual(r.returncode,20,r.stderr)
        self.assertIn('first unsupported PS4 import: after-init',r.stdout)
        self.assertIn('_init_env=1',r.stdout)
        strict = self.run_image(data,'--strict-imports')
        self.assertEqual(strict.returncode,20,strict.stderr)
        self.assertIn('first unsupported PS4 import: bzQExy189ZI#q#q',strict.stdout)

    def test_unverified_runtime_stays_disabled(self):
        r = self.run_image(package(b'\xff\x25\x02\0\0\0\x90\x90',[(8,1,0,0)],['bzQExy189ZI#q#q'],0))
        self.assertEqual(r.returncode,20,r.stderr)
        self.assertIn('_init_env=0',r.stdout)

    def test_unknown_capabilities_rejected(self):
        r = self.run_image(package(b'\xc3',capabilities=2))
        self.assertEqual(r.returncode,1)
        self.assertIn('unknown runtime capabilities',r.stderr)


if __name__ == '__main__':
    unittest.main()
