import os
import io
from PIL import Image
from rembg import remove

input_dir = r"c:\Users\PC\Drafting\iconos_crudos"
output_dir = r"c:\Users\PC\Drafting\drafting\android\app\src\main\res\drawable"

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

files_to_process = {
    "general.png": "ic_general.png",
    "maestria.png": "ic_otp.png",
    "objeto.png": "ic_in_game.png"
}

for in_name, out_name in files_to_process.items():
    in_path = os.path.join(input_dir, in_name)
    out_path = os.path.join(output_dir, out_name)
    
    if not os.path.exists(in_path):
        print(f"File {in_path} not found")
        continue

    print(f"Processing {in_name}...")
    
    # 1. Quitar fondo con rembg
    with open(in_path, 'rb') as i:
        input_data = i.read()
    
    output_data = remove(input_data)
    
    # 2. Abrir imagen sin fondo
    img = Image.open(io.BytesIO(output_data)).convert("RGBA")
    
    # 3. Convertir píxeles no transparentes a blanco puro
    data = img.getdata()
    new_data = []
    
    for item in data:
        r, g, b, a = item
        if a > 10:  # Tiene algo de opacidad
            new_data.append((255, 255, 255, a))
        else:
            new_data.append((255, 255, 255, 0))
            
    img.putdata(new_data)
    
    # Resize a un tamaÃ±o estandar de icono (por ejemplo 128x128 maximo)
    img.thumbnail((128, 128), Image.Resampling.LANCZOS)
    
    img.save(out_path, "PNG")
    print(f"Saved {out_name} to {out_path}")
