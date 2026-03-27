# earth_engine_service.py
import ee
import json
from datetime import datetime, timedelta

# Initialize Earth Engine
ee.Authenticate()
ee.Initialize(project='clim8-hackathon')

def get_flood_risk_index(lat: float, lng: float, radius_km: float = 10):
    """
    Query flood risk index using satellite data.
    Combines soil moisture, precipitation, and elevation.
    """
    point = ee.Geometry.Point([lng, lat])
    region = point.buffer(radius_km * 1000)

    end_date = datetime.now()
    start_date = end_date - timedelta(days=7)

    # NASA SMAP Soil Moisture
    soil_moisture = (ee.ImageCollection('NASA/SMAP/SPL4SMGP/007')
        .filterDate(start_date.isoformat(), end_date.isoformat())
        .select('sm_surface')
        .mean()
        .reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=region,
            scale=1000
        ).getInfo())

    # GPM Precipitation
    precipitation = (ee.ImageCollection('NASA/GPM_L3/IMERG_V06')
        .filterDate(start_date.isoformat(), end_date.isoformat())
        .select('precipitationCal')
        .sum()
        .reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=region,
            scale=10000
        ).getInfo())

    # SRTM Elevation (low elevation = higher flood risk)
    elevation = (ee.Image('USGS/SRTMGL1_003')
        .reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=region,
            scale=30
        ).getInfo())

    # Compute composite risk score (0-1)
    soil_sat = min((soil_moisture.get('sm_surface', 0) / 0.5), 1.0) * 100
    precip_risk = min((precipitation.get('precipitationCal', 0) / 500), 1.0)
    elev_risk = max(0, 1 - (elevation.get('elevation', 0) / 500))

    flood_risk = (soil_sat/100 * 0.4) + (precip_risk * 0.4) + (elev_risk * 0.2)

    return {
        'flood_risk_index': round(flood_risk, 3),
        'soil_saturation_pct': round(soil_sat, 1),
        'precipitation_7d_mm': round(precipitation.get('precipitationCal', 0), 1),
        'elevation_m': round(elevation.get('elevation', 0), 1),
        'cyclone_probability': estimate_cyclone_prob(lat, lng),
        'risk_level': classify_risk(flood_risk),
        'region': f'{lat:.4f}N, {lng:.4f}E',
        'computed_at': datetime.now().isoformat(),
    }

def classify_risk(score: float) -> str:
    if score > 0.8: return 'severe'
    if score > 0.6: return 'high'
    if score > 0.3: return 'moderate'
    return 'safe'

def estimate_cyclone_prob(lat: float, lng: float) -> float:
    """Simplified cyclone probability based on season + location."""
    from datetime import datetime
    month = datetime.now().month
    # Kerala cyclone season: Oct-Dec
    seasonal_factor = 0.6 if month in [10, 11, 12] else 0.1 if month in [5, 6] else 0.05
    # Coastal proximity boost
    coastal_factor = 1.2 if lng > 75 else 0.5
    return min(round(seasonal_factor * coastal_factor, 2), 1.0)


# Usage:
# result = get_flood_risk_index(9.9312, 76.2673)  # Kochi, Kerala
# print(json.dumps(result, indent=2))