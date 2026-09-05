import os
import re

directory = r'c:\Users\PC\Drafting\backend\golang'
pattern = re.compile(r'"(plus|pro|ultra|creator_plus|creator_pro|creator_ultra)_(1d|1w|1m|1y)"')

for root, dirs, files in os.walk(directory):
    for file in files:
        if file.endswith('.go'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            new_content = pattern.sub(r'"sub_\1_\2"', content)
            
            if new_content != content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Updated {filepath}")
