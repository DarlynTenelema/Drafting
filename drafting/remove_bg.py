from PIL import Image
import os

images = [
    'chest_outline.png',
    'chest_solid.png',
    'scroll_outline.png',
    'scroll_solid.png',
    'crystal_coin_outline.png',
    'crystal_coin_solid.png'
]

base_dir = r"c:\Users\PC\Drafting\drafting\assets\images"

for img_name in images:
    path = os.path.join(base_dir, img_name)
    if not os.path.exists(path):
        continue
    
    img = Image.open(path).convert("RGBA")
    data = img.getdata()
    
    new_data = []
    for item in data:
        # Check if the pixel is gray (r~=g~=b)
        # and not too bright (background grid is usually dark/mid gray)
        r, g, b, a = item
        
        # Calculate max diff between channels to see if it's gray
        max_diff = max(abs(r-g), abs(r-b), abs(g-b))
        
        # If it's a white icon on a gray grid:
        # The grid is usually around 60-150 RGB.
        brightness = (r + g + b) / 3
        
        # If it's bright white, keep it. 
        if brightness > 160: 
            if brightness > 220:
                new_data.append((255, 255, 255, 255))
            else:
                # Anti-aliasing
                alpha = int((brightness - 160) / (255 - 160) * 255)
                new_data.append((255, 255, 255, alpha))
        else:
            new_data.append((255, 255, 255, 0))
            
    img.putdata(new_data)
    img.save(path, "PNG")
    print(f"Processed {img_name}")
