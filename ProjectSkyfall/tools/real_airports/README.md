# Real airport layouts

1. `extract.py ICAO,... infra|bldg` (needs `ovt.py`): reads OpenStreetMap-derived airport features and
   building footprints for each airport from the public Overture Maps release on S3 (HTTP range reads).
   Also download `runways.csv` (OurAirports) and FlightGear's `Airports/apt.dat.gz` into the same folder.
2. `convert.py SRC_DIR OUT_DIR ICAO,...`: builds the layout files (runways, noded taxiway network with
   holding points, gates with real headings, pavement triangles, building footprints, tower, fence).
3. `apply.py OUT_DIR ICAO,...` (from the project root): installs the files, rewrites the runways in
   `src/data/airports.gd` and regenerates `src/data/real_airports.gd`.
4. `plot.py OUT_DIR ICAO out.png`: top-down plot for checking a layout.
