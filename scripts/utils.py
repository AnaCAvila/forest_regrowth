import ee
import geemap
from functools import partial

# Authenticate to Earth Engine
try:
  ee.Initialize()
except Exception as e:
  ee.Authenticate()
  ee.Initialize(project='ee-ana-zonia')

'''
Choose region and import corresponding shapefile. Can be:
        br_amazon -> the Amazon biome in Brazilian territory
        br -> entire Brazil
        panamaz -> entire Amazonia, including territory across all Amazonian countries.
        
        *** panamaz has less land use categories and data processing is still unfinished for this data ***
        "projects/mapbiomasraisg/public/collection1/mapbiomas_raisg_panamazonia_collection1_integration_v1"
'''

def import_roi(region):
    if region == "br_amazon":
        return ee.FeatureCollection("projects/ee-ana-zonia/assets/br_biomes").filter(ee.Filter.eq("id", 18413)).geometry()
    else:
        return ee.FeatureCollection("projects/ee-ana-zonia/assets/br_biomes").geometry().dissolve()


def export_grid_cell(grid_cell, img, name):
    img_export = img.clip(grid_cell)
    
    task = ee.batch.Export.image.toDrive(
        image = img_export,
        description = name,
        folder = name,
        scale = 30,
        region = grid_cell.geometry(),
        maxPixels = 1e11
    )
    return task.id

def export_image_as_grid(img, name, region):
    roi = import_roi(region)
    fishnet = geemap.fishnet(roi, h_interval=2.0, v_interval=2.0, delta=0.5)
    partial_export_grid_cell = partial(export_grid_cell, img=img, name=name) 
    # fishnet.map(partial_export_grid_cell)
    task_ids = fishnet.map(partial_export_grid_cell)
    
    for task_id in task_ids.getInfo():
        task = ee.batch.Task.get(task_id)
        ee.batch.Task.start(task)

