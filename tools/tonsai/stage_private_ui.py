"""Optimize only the explicitly approved private UI assets; never write to source."""
import argparse
import shutil
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);a=p.parse_args()
a.destination.mkdir(parents=True,exist_ok=True)
for name,width in [('logo.png',1024),('rect-button.png',384),('rect-button-1.png',512),('parch-portrait.png',640),('parch-landscape.png',960)]:
    with Image.open(a.source/name) as image:
        image=image.convert('RGBA');image=image.crop(image.getbbox())
        image.resize((width,round(image.height*width/image.width)),Image.Resampling.LANCZOS).save(a.destination/name,optimize=True)
shutil.copyfile(a.source/'Survivant.ttf',a.destination/'Survivant.ttf')
