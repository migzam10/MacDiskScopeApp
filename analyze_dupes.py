#!/usr/bin/env python3
import os
import hashlib
from collections import defaultdict
import sys

# Diccionarios para almacenar información
hash_map = defaultdict(list)      # hash -> lista de (ruta, tamaño, nombre)
name_map = defaultdict(list)      # nombre -> lista de (ruta, hash, tamaño)

print("🔍 Analizando archivos...", file=sys.stderr)

count = 0
for root, dirs, files in os.walk('.'):
    # Ignorar directorios de sistema
    dirs[:] = [d for d in dirs if d != '.DS_Store']
    
    for file in files:
        if file == '.DS_Store':
            continue
            
        filepath = os.path.join(root, file)
        try:
            # Obtener tamaño
            size = os.path.getsize(filepath)
            
            # Calcular hash
            with open(filepath, 'rb') as f:
                file_hash = hashlib.md5(f.read()).hexdigest()
            
            # Guardar información
            hash_map[file_hash].append((filepath, size, file))
            name_map[file].append((filepath, file_hash, size))
            
            count += 1
            if count % 1000 == 0:
                print(f"Procesados {count} archivos...", file=sys.stderr)
                
        except Exception as e:
            print(f"Error procesando {filepath}: {e}", file=sys.stderr)

print(f"\nTotal procesados: {count} archivos\n", file=sys.stderr)

# SECCIÓN 1: Duplicados por contenido (mismo hash)
print("╔════════════════════════════════════════════════════════════════╗")
print("║     DUPLICADOS POR CONTENIDO (Mismo contenido = Mismo hash)    ║")
print("╚════════════════════════════════════════════════════════════════╝\n")

dup_count = 0
for file_hash, paths in sorted(hash_map.items()):
    if len(paths) > 1:
        dup_count += len(paths) - 1
        print(f"🔴 DUPLICADO #{dup_count // (len(paths)-1) + 1}")
        print(f"   Hash MD5: {file_hash}")
        print(f"   Tamaño: {paths[0][1]:,} bytes")
        print(f"   Archivos encontrados: {len(paths)}")
        for i, (filepath, size, name) in enumerate(paths, 1):
            print(f"   {i}. {filepath}")
        print()

# SECCIÓN 2: Mismo nombre pero diferente contenido
print("\n╔════════════════════════════════════════════════════════════════╗")
print("║   ARCHIVOS CON MISMO NOMBRE PERO DIFERENTE CONTENIDO          ║")
print("╚════════════════════════════════════════════════════════════════╝\n")

for filename, paths_info in sorted(name_map.items()):
    if len(paths_info) > 1:
        hashes = set(p[1] for p in paths_info)
        if len(hashes) > 1:  # Diferente contenido
            print(f"⚠️  Nombre: {filename}")
            print(f"    Encontrado {len(paths_info)} veces con diferente contenido:")
            for filepath, file_hash, size in paths_info:
                print(f"    • {filepath}")
                print(f"      Hash: {file_hash} | Tamaño: {size:,} bytes")
            print()

