CREATE OR REPLACE FUNCTION st_polygrid(geometry, numeric) RETURNS geometry AS
$$
SELECT
    ST_SetSRID(ST_Collect(ST_POINT(x,y)), ST_SRID($1))
FROM
    generate_series(ST_XMin($1)::numeric, ST_xmax($1)::numeric, $2) as x,
    generate_series(ST_ymin($1)::numeric, ST_ymax($1)::numeric,$2) as y 
WHERE
    ST_Intersects($1,ST_SetSRID(ST_POINT(x,y), ST_SRID($1)))
$$
LANGUAGE sql VOLATILE;

--the st_polygrid function creates a pointgrid (MULTIPOINT) with customizable resolution in a certain geometry or area
--Example: st_polygrid(area.geometry, 0.1)

DROP TABLE IF EXISTS landuse_res;
DROP TABLE IF EXISTS multipoint_grid;
DROP TABLE IF EXISTS points_res;
DROP TABLE IF EXISTS gridandpoints;
DROP TABLE IF EXISTS population;
   
--pointgrid in study_area

CREATE TABLE multipoint_grid as
WITH x AS (
	SELECT st_union(study_area.geom) as geom
	FROM study_area
)
SELECT st_polygrid(x.geom,0.0005) AS geom
FROM x;

--Intersection of the pointgrid with landuse and census data

CREATE TABLE points_res as
WITH x AS
(
	SELECT (st_dump(geom) ).geom as geom
	FROM multipoint_grid
),
landuse_res as (
    SELECT *
    FROM landuse l
    WHERE l.landuse NOT IN (SELECT UNNEST(variable_array) FROM variable_container WHERE identifier = 'custom_landuse_no_residents');
)
SELECT x.*, c.gid as gid
FROM x, landuse_res l, census c
WHERE st_intersects(x.geom,l.geom) AND st_intersects(x.geom,c.geom);

--counting the point in each census-field

CREATE TABLE gridandpoints AS
SELECT p.gid, sum(ST_NPoints(p.geom)) as npoints
FROM points_res p, census c
WHERE p.gid=c.gid
GROUP BY p.gid;

ALTER TABLE gridandpoints ADD COLUMN pop integer;
ALTER TABLE gridandpoints ADD COLUMN pop_per_point integer;

--calculation of population per point

UPDATE gridandpoints 
SET pop = census.pop::integer
FROM census
WHERE gridandpoints.gid = census.gid;

UPDATE gridandpoints SET pop_per_point = pop/npoints;

--creation of the population table

CREATE TABLE population as
SELECT points_res.*, gridandpoints.pop_per_point as population
FROM points_res, gridandpoints
WHERE points_res.gid = gridandpoints.gid;

CREATE INDEX index_population ON population USING GIST (geom);
ALTER TABLE population ADD COLUMN gid serial;
ALTER TABLE population ADD PRIMARY KEY(gid);