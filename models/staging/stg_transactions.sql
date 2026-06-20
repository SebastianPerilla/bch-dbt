{{ config(materialized='view') }}

with raw_transactions as (
    select
        `hash` as tx_hash,
        block_timestamp,
        date(block_timestamp) as block_date,
        inputs,
        outputs
    from {{ source('public_bch', 'transactions') }}
)

select *
from raw_transactions
-- Filters for the last 3 months relative to the maximum date in the table
where block_date >= date_sub((select max(date(block_timestamp)) from {{ source('public_bch', 'transactions') }}), interval 3 month)
