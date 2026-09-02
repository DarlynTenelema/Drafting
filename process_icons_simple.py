import os
from PIL import Image, ImageDraw

input_dir = r"c:\Users\PC\Drafting\iconos_crudos"
output_dir = r"c:\Users\PC\Drafting\drafting\android\app\src\main\res\drawable"

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

files_to_process = {
    "general.png": "ic_general.png",
    "maestria.png": "ic_otp.png",
    "objeto.png": "ic_in_game.png"
}

def remove_background_simple(img):
    img = img.convert("RGBA")
    
    # 1. Asumimos que el fondo suele ser oscuro o de un color sÃ³lido en las esquinas
    # Si la imagen ya tiene alfa, quizÃ¡ ya es transparente
    # Haremos un floodfill desde las esquinas con un threshold
    # Pero para iconos simples en blanco, mejor tomar los pixeles oscuros y volverlos fondo.
    
    data = img.getdata()
    new_data = []
    
    for item in data:
        r, g, b, a = item
        brightness = (r+g+b)/3.0
        
        # Si es suficientemente brillante y no es transparente
        if brightness > 40 and a > 20: 
            new_data.append((255, 255, 255, 255))
        else:
            new_data.append((255, 255, 255, 0))
            
    img.putdata(new_data)
    return img

for in_name, out_name in files_to_process.items():
    in_path = os.path.join(input_dir, in_name)
    out_path = os.path.join(output_dir, out_name)
    
    if not os.path.exists(in_path):
        continue

    try:
        print(f"Processing {in_name}...")
        img = Image.open(in_path)
        img = remove_background_simple(img)
        img.thumbnail((128, 128), Image.Resampling.LANCZOS)
        img.save(out_path, "PNG")
        print(f"Saved {out_name} to {out_path}")
    except Exception as e:
        print(f"Error {e}")
