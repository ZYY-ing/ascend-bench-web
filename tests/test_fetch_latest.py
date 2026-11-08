"""Exercise the real Bash downloader and README commands without network/Docker."""
import hashlib
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
REF = 'a' * 40


def bash_executable():
    if os.name == 'nt':
        git = shutil.which('git')
        if git:
            candidate = Path(git).parent.parent/'bin/bash.exe'
            if candidate.is_file(): return str(candidate)
        return None
    return shutil.which('bash')


@unittest.skipUnless(bash_executable(), 'Bash required for downloader integration')
class LatestDownloadTests(unittest.TestCase):
    def setUp(self):
        output = ROOT/'outputs'
        output.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='fetch-latest-test-', dir=output)
        self.root = Path(self.temp.name).resolve()
        assert self.root.is_relative_to(output.resolve())
        self.addCleanup(self.temp.cleanup)
        (self.root/'scratch').mkdir()
        (self.root/'session').mkdir()
        self.marker = self.root/'installed'
        self.calls = self.root/'calls'
        for name, label in [('latest', 'latest'), ('stale', 'stale')]:
            raw = ('#!/usr/bin/env bash\nprintf "'+label+'\\n" >> "$TEST_INSTALL_MARKER"\nprintf "%s\\n" "$@" >> "$TEST_INSTALL_MARKER"\n').encode()
            with tarfile.open(self.root/(name+'.tar.gz'), 'w:gz') as archive:
                member = tarfile.TarInfo('ascend-bench-kit/setup.sh')
                member.size = len(raw)
                archive.addfile(member, io.BytesIO(raw))
        digest = hashlib.sha256((self.root/'latest.tar.gz').read_bytes()).hexdigest()
        (self.root/'checksum').write_bytes((digest+'  ascend-bench-kit.tar.gz\n').encode())
        self.hook = self.root/'hook.sh'
        self.hook.write_text('''curl() {
 local output="" url="" previous="" arg proxied="no"
 for arg in "$@"; do
  [ "$previous" != "-o" ] || output="$arg"
  [ "$arg" != "-x" ] || proxied="yes"
  case "$arg" in https://*) url="$arg";; esac
  previous="$arg"
 done
 printf '%s|%s\\n' "$url" "$proxied" >> "$TEST_CALLS"
 [ -n "$output" ] || output=/dev/stdout
 if [ "$TEST_CASE" = "proxy" ] && [ "$proxied" = "no" ]; then return 22; fi
 case "$url" in
  */commits/main*)
   case "$TEST_CASE" in metadata_unavailable|git_fallback) return 22;; esac
   if [ "$TEST_CASE" = "invalid_metadata" ]; then printf '{"sha":"main"}' > "$output"
   else printf '{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' > "$output"; fi
   ;;
  */fetch-ascend-bench.sh*) cp "$TEST_SCRIPT" "$output";;
  *.sha256*)
   if [ "$TEST_CASE" = "invalid_checksum" ]; then printf 'bad checksum file' > "$output"
   else cp "$TEST_CHECKSUM" "$output"; fi
   ;;
  *ascend-bench-kit.tar.gz*)
   if [[ "$url" == https://api.github.com/* ]]; then
    [[ "$*" == *'Accept: application/vnd.github.raw+json'* ]] || return 23
   fi
   if [ "$TEST_CASE" = "all_stale" ]; then cp "$TEST_STALE" "$output"
   elif [ "$TEST_CASE" = "api_fallback" ] && [[ "$url" == https://raw.githubusercontent.com/* ]]; then cp "$TEST_STALE" "$output"
   elif [ "$TEST_CASE" = "cdn_fallback" ] && [[ "$url" != https://cdn.jsdelivr.net/* ]]; then cp "$TEST_STALE" "$output"
   else cp "$TEST_LATEST" "$output"; fi
   ;;
  *) return 24;;
 esac
}
python3() { "$TEST_PYTHON" "$@"; }
git() {
 [ "$TEST_CASE" = "git_fallback" ] || return 22
 printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\trefs/heads/main\\n'
}
sleep() { :; }
''', encoding='utf-8', newline='\n')

    def run_script(self, case='latest', ref=None, commands=None, download_only=False):
        environment = {**os.environ, 'BASH_ENV': self.hook.as_posix(),
            'TMPDIR': (self.root/'scratch').as_posix(), 'TEST_CASE': case,
            'TEST_CALLS': self.calls.as_posix(), 'TEST_INSTALL_MARKER': self.marker.as_posix(),
            'TEST_PYTHON': Path(sys.executable).as_posix(),
            'TEST_SCRIPT': (ROOT/'fetch-ascend-bench.sh').as_posix(),
            'TEST_CHECKSUM': (self.root/'checksum').as_posix(),
            'TEST_LATEST': (self.root/'latest.tar.gz').as_posix(),
            'TEST_STALE': (self.root/'stale.tar.gz').as_posix(),
            'ASCEND_BENCH_PROXY': 'http://proxy.example:3128' if case == 'proxy' else '',
            'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8'}
        environment.pop('ASCEND_BENCH_REF', None)
        if ref is not None: environment['ASCEND_BENCH_REF'] = ref
        if commands is None:
            args = [bash_executable(), str(ROOT/'fetch-ascend-bench.sh')]
            args += ['--download-only', str(self.root/'download')] if download_only else ['fixture-container', '/fixture/project', '18788']
        else:
            script = self.root/'commands.sh'
            script.write_text(commands.replace('<测试容器名>', 'fixture-container').replace('<容器内持久化项目目录>', '/fixture/project'), encoding='utf-8', newline='\n')
            args = [bash_executable(), str(script)]
        result = subprocess.run(args, cwd=self.root/'session', env=environment, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=30)
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        for call in calls:
            self.assertNotIn('@main', call)
            self.assertNotIn('/main/dist/', call)
            if '/dist/' in call:
                self.assertIn(REF, call)
        return result, calls

    def assert_installed_once(self, result):
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(self.marker.read_text().splitlines().count('latest'), 1)
        self.assertNotIn('stale', self.marker.read_text())

    def test_latest_main_uses_one_snapshot_and_keeps_setup_arguments(self):
        result, calls = self.run_script()
        self.assert_installed_once(result)
        self.assertEqual(self.marker.read_text().splitlines(), ['latest','fixture-container','/fixture/project','','18788'])
        self.assertEqual(sum('/commits/main' in c for c in calls), 1)

    def test_valid_tar_with_wrong_hash_is_rejected_then_api_used(self):
        result, calls = self.run_script('api_fallback')
        self.assert_installed_once(result)
        self.assertTrue(any('/contents/dist/ascend-bench-kit.tar.gz?' in c for c in calls))

    def test_cdn_fallback_uses_full_commit_after_wrong_packages(self):
        result, calls = self.run_script('cdn_fallback')
        self.assert_installed_once(result)
        self.assertTrue(any('cdn.jsdelivr.net/gh/' in c and '@'+REF in c for c in calls))

    def test_all_stale_packages_never_execute_setup(self):
        result, _ = self.run_script('all_stale')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_unavailable_metadata_and_bad_metadata_stop_before_package(self):
        for case in ('metadata_unavailable', 'invalid_metadata'):
            with self.subTest(case=case):
                self.calls.unlink(missing_ok=True)
                result, calls = self.run_script(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.marker.exists())
                self.assertFalse(any('/dist/' in c for c in calls))

    def test_explicit_commit_works_without_metadata_endpoint(self):
        result, calls = self.run_script('metadata_unavailable', REF)
        self.assert_installed_once(result)
        self.assertFalse(any('/commits/main' in c for c in calls))

    def test_git_fallback_automatically_resolves_main(self):
        result, _ = self.run_script('git_fallback')
        self.assert_installed_once(result)

    def test_download_only_saves_verified_package_without_setup(self):
        result, _ = self.run_script(download_only=True)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertFalse(self.marker.exists())
        self.assertEqual((self.root/'download/ascend-bench-kit.tar.gz').read_bytes(), (self.root/'latest.tar.gz').read_bytes())
        self.assertEqual((self.root/'download/source-commit.txt').read_text().strip(), REF)

    def test_failed_download_does_not_overwrite_previous_download(self):
        destination=self.root/'download'
        destination.mkdir()
        (destination/'ascend-bench-kit.tar.gz').write_bytes(b'previous verified download')
        result, _ = self.run_script('all_stale', download_only=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((destination/'ascend-bench-kit.tar.gz').read_bytes(), b'previous verified download')
        self.assertFalse(self.marker.exists())

    def test_bad_checksum_never_downloads_or_installs_package(self):
        result, calls = self.run_script('invalid_checksum')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())
        self.assertFalse(any('tar.gz|' in c for c in calls))

    def test_proxy_fallback_preserved_without_printing_proxy_address(self):
        result, calls = self.run_script('proxy')
        self.assert_installed_once(result)
        self.assertTrue(any(c.endswith('|yes') for c in calls))
        self.assertNotIn('proxy.example', result.stdout+result.stderr)

    def test_branch_alias_cannot_be_used_as_explicit_commit(self):
        result, calls = self.run_script(ref='main')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(calls)
        self.assertFalse(self.marker.exists())

    def test_readme_public_steps_and_both_install_options(self):
        readme = (ROOT/'README.md').read_text(encoding='utf-8')
        start = readme.index('### 第 1 步')
        end = readme.index('### 第 2 步', start)
        blocks = re.findall(r'```bash\n(.*?)\n```', readme[start:end], re.S)
        self.assertEqual(len(blocks), 3)
        for option in (blocks[0], blocks[1]+'\n'+blocks[2]):
            with self.subTest(option='one-click' if 'f.sh' in option else 'manual'):
                self.marker.unlink(missing_ok=True)
                self.calls.unlink(missing_ok=True)
                result, _ = self.run_script(commands=option)
                self.assert_installed_once(result)


if __name__ == '__main__':
    unittest.main()
