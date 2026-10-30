from pathlib import Path
import zipfile
root=Path(__file__).resolve().parents[1]
source=(root/'HOTEL_SHIFT/Views/StaffAndOtherViews.swift').read_text()
assert 'private enum StaffPhotoDecodeCache' in source
assert 'cache.totalCostLimit = 32 * 1024 * 1024' in source
assert 'StaffPhotoDecodeCache.image(from: data)' in source
assert 'StaffPhotoDecodeCache.image(from: photoData)' in source
assert 'UIImage(data: rawData)' in source  # compression still uses source bytes
print('FIXED108 static checks OK')
