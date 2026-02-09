import trimesh
import os
import pandas as pd
import time

# --- NASTAVENÍ ---
slozka = r"C:\Users\Tomea\Downloads\bluecat-codekit-main(1)\bluecat-codekit-main\cesnet\rayprocess\RCT\Volume_Workflow\results\mesh"  # Cesta ke složce s PLY soubory (./ je aktuální složka)
vystupni_csv = "vysledky_objemu.csv"

def zpracovat_meshe(input_folder, output_file):
    soubory = [f for f in os.listdir(input_folder) if f.lower().endswith('.ply')]
    pocet = len(soubory)
    
    if pocet == 0:
        print("Nebyly nalezeny žádné .ply soubory.")
        return

    data = []
    print(f"Nalezeno {pocet} souborů. Začínám výpočet...")
    
    start_time = time.time()

    for i, soubor in enumerate(soubory):
        cesta = os.path.join(input_folder, soubor)
        
        try:
            # Načtení meshe
            # force='mesh' zajistí, že se to nenačte jako Scene, ale jako jeden objekt
            mesh = trimesh.load(cesta, force='mesh')
            
            # Výpočet objemu
            # Trimesh používá Gaussovu větu o divergenci (surface integral)
            objem = mesh.volume
            
            # Užitečné info navíc: Je mesh matematicky uzavřený?
            # Pokud CloudCompare objem spočítal, je to ok, ale trimesh 
            # může vrátit False, pokud jsou tam drobné duplicitní hrany atd.
            is_watertight = mesh.is_watertight
            
            # Přidání do seznamu
            data.append({
                "Soubor": soubor,
                "Objem": objem,
                "Watertight": is_watertight,
                "Pocet_sten": len(mesh.faces)
            })
            
            print(f"[{i+1}/{pocet}] {soubor}: {objem:.6f}")

        except Exception as e:
            print(f"CHYBA u souboru {soubor}: {e}")
            data.append({
                "Soubor": soubor,
                "Objem": None,
                "Watertight": False,
                "Pocet_sten": 0,
                "Error": str(e)
            })

    # Uložení do CSV
    df = pd.DataFrame(data)
    df.to_csv(output_file, index=False, sep=';') # Středník pro Excel v CZ
    
    celkovy_cas = time.time() - start_time
    print("-" * 30)
    print(f"Hotovo. Zpracováno za {celkovy_cas:.2f} sekund.")
    print(f"Výsledky uloženy do: {output_file}")
    
    # Rychlý součet
    total_vol = df['Objem'].sum()
    print(f"Celkový objem všech souborů: {total_vol:.4f}")

if __name__ == "__main__":
    zpracovat_meshe(slozka, vystupni_csv)