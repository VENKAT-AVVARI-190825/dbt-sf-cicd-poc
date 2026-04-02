{{ config(
    materialized='incremental',
    unique_key='event_id',
    cluster_by=['event_date']
) }}

WITH raw AS (
    SELECT
        $1:event_id::STRING        AS event_id,
        $1:event_type::STRING      AS event_type,
        $1:media_asset_id::STRING  AS media_asset_id,
        $1:user_id::STRING         AS user_id,
        $1:region::STRING          AS region,
        $1:ingested_at::TIMESTAMP  AS ingested_at,
        TO_DATE($1:ingested_at)    AS event_date,
        $1:source_key::STRING      AS source_key
    FROM @media_raw_stage
    (FILE_FORMAT => 'json_format')
)

SELECT * FROM raw

{% if is_incremental() %}
WHERE ingested_at > (SELECT COALESCE(MAX(ingested_at), '1900-01-01') FROM {{ this }})
{% endif %}
