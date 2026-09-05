import os
import re

directory = r'c:\Users\PC\Drafting'
# Exclude .git and other non-relevant directories to speed up
exclude_dirs = {'.git', '.github', 'node_modules', '.dart_tool', 'build', 'windows', 'linux', 'macos', 'ios', 'android'}

pattern = re.compile(r"['\"](plus|pro|ultra|creator_plus|creator_pro|creator_ultra)_(1d|1w|1m|1y)['\"]")

def replace_match(match):
    # Keep the original quote character
    quote = match.group(0)[0]
    return f"{quote}sub_{match.group(1)}_{match.group(2)}{quote}"

for root, dirs, files in os.walk(directory):
    dirs[:] = [d for d in dirs if d not in exclude_dirs]
    for file in files:
        if file.endswith(('.go', '.dart', '.sql', '.md')):
            filepath = os.path.join(root, file)
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                new_content = pattern.sub(replace_match, content)
                
                if new_content != content:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Updated {filepath}")
            except Exception as e:
                print(f"Skipping {filepath}: {e}")
