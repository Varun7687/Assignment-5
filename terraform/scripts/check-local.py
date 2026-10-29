"""Offline consistency/syntax checks. NOT a replacement for terraform validate/plan."""
from pathlib import Path
import ast
import base64
import json
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
TF = '\n'.join(p.read_text() for p in ROOT.glob('*.tf'))


def render_template(name, values):
    text = (ROOT / 'scripts' / name).read_text()
    text = re.sub(r'%\{.*?\}', '', text)
    def substitute(match):
        expression = match.group(1).strip()
        if expression.startswith('base64encode('):
            key = expression[len('base64encode('):-1]
            return base64.b64encode(values[key].encode()).decode()
        return values[expression]
    return re.sub(r'\$\{([^{}]+)\}', substitute, text)


class LocalChecks(unittest.TestCase):
    def test_variable_references(self):
        declared = set(re.findall(r'variable\s+"([\w]+)"', TF))
        referenced = set(re.findall(r'\bvar\.([\w]+)', TF))
        self.assertFalse(referenced - declared, referenced - declared)

    def test_resource_references(self):
        declared = {f'{a}.{b}' for a, b in re.findall(r'resource\s+"([\w]+)"\s+"([\w]+)"', TF)}
        data = {f'data.{a}.{b}' for a,b in re.findall(r'data\s+"([\w]+)"\s+"([\w]+)"', TF)}
        data_refs = set(re.findall(r'\bdata\.(aws_[\w]+\.[\w]+)', TF))
        self.assertFalse({'data.' + x for x in data_refs} - data)
        without_data = re.sub(r'\bdata\.aws_[\w]+\.[\w]+', '', TF)
        referenced = set(re.findall(r'\b((?:aws|random)_[\w]+\.[\w]+)', without_data))
        self.assertFalse(referenced - declared, referenced - declared)

    def test_file_dependencies(self):
        refs = re.findall(r'\$\{path.module\}/([^"\n]+)', TF)
        for relative in refs:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_policy_json(self):
        for file in (ROOT / 'iam').glob('*.json'):
            policy = json.loads(file.read_text())
            self.assertEqual(policy['Version'], '2012-10-17')
            self.assertTrue(policy['Statement'])

    def test_python_syntax(self):
        for file in list((ROOT / 'scripts').glob('*.py')) + [ROOT.parent / 'app.py']:
            ast.parse(file.read_text(), filename=str(file))

    def test_rendered_shell_and_userdata_size(self):
        values = {
            'username':'admin1', 'public_key':'ssh-ed25519 TEST admin1',
            'aws_region':'us-east-1',
            'db_host':'db.prod.bluefin.internal',
            'db_secret_arn':'arn:aws:secretsmanager:us-east-1:123456789012:secret:bluefin-app-example',
            'master_secret_arn':'arn:aws:secretsmanager:us-east-1:123456789012:secret:bluefin-master-example',
            'sns_topic_arn':'arn:aws:sns:us-east-1:123456789012:bluefin-landing-zone-operations',
            'backup_bucket':'bluefin-landing-zone-123456789012-backups',
            'app_py':(ROOT.parent / 'app.py').read_text(),
            'index_html':(ROOT.parent / 'templates/index.html').read_text(),
            'requirements_txt':(ROOT.parent / 'requirements.txt').read_text(),
            'bootstrap_py':(ROOT / 'scripts/bootstrap-db.py').read_text(),
            'backup_py':(ROOT / 'scripts/db-backup.py').read_text()
        }
        for name in ['app-user-data.sh.tftpl', 'backup-user-data.sh.tftpl', 'bastion-user-data.sh.tftpl']:
            rendered = render_template(name, values)
            result = subprocess.run(['bash','-n'], input=rendered, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, name + ': ' + result.stderr)
            self.assertLess(len(rendered.encode()), 16384, name + ' exceeds EC2 user-data limit')
            print(f'{name}: sample rendered size {len(rendered.encode())} bytes')
        result = subprocess.run(['bash','-n',str(ROOT/'scripts/dev-user-data.sh')], capture_output=True)
        self.assertEqual(result.returncode,0)

    def test_no_credentials_or_saved_plans(self):
        for file in ROOT.rglob('*'):
            if not file.is_file() or '__pycache__' in file.parts:
                continue
            self.assertFalse(file.name.endswith(('.tfstate','.tfplan','.pem','.key')), str(file))
            content = file.read_text()
            self.assertFalse(re.search(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',content), str(file))
            self.assertNotIn('BEGIN ' + 'OPENSSH ' + 'PRIVATE KEY',content)

    def test_no_discovery_lookup(self):
        self.assertNotIn('data "aws_ami"',TF)
        self.assertNotIn('data "aws_availability_zones"',TF)
        self.assertNotIn('data.aws_ami.amazon_linux',TF)

    def test_hcl_balanced_delimiters(self):
        # Basic lexical check only; cannot check Terraform schemas/semantics.
        for file in ROOT.glob('*.tf'):
            s=file.read_text(); stack=[]; i=0; quote=False
            while i<len(s):
                c=s[i]
                if quote:
                    if c=='\\': i+=2;continue
                    if c=='"': quote=False
                else:
                    if s.startswith('//',i) or c=='#':
                        end=s.find('\n',i);i=len(s) if end<0 else end;continue
                    if s.startswith('/*',i):
                        end=s.find('*/',i+2);self.assertNotEqual(end,-1,str(file));i=end+2;continue
                    if c=='"':quote=True
                    elif c in '{[(':stack.append(c)
                    elif c in '}])':
                        self.assertTrue(stack,str(file))
                        self.assertEqual(stack.pop(),{'}':'{',']':'[',')':'('}[c],str(file))
                i+=1
            self.assertFalse(quote,str(file));self.assertFalse(stack,str(file))

if __name__ == '__main__':
    unittest.main(verbosity=2)
