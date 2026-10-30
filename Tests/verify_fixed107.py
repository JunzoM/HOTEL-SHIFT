from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'HOTEL_SHIFT'
source = (root / 'Views' / 'StaffAndOtherViews.swift').read_text()
assert 'image.preparingThumbnail(of: CGSize(width: 640, height: 640))' in source
assert 'thumbnail.jpegData(compressionQuality: 0.80)' in source
assert 'image.preparingThumbnail(of: CGSize(width: 1000, height: 700))' in source
print('FIXED107 source regression checks passed')
