{{ config(
    materialized='table',
    schema='mart'
) }}

with historical_transactions as (
    -- Querying the raw public dataset directly to compute lifetime balances accurately
    select * from `bigquery-public-data.crypto_bitcoin_cash.transactions`
),

-- 1. Unnest outputs to find what every address received
received_amounts as (
    select
        output.addresses as address_array,
        output.value as value
    from historical_transactions tx,
    unnest(outputs) as output
),

flattened_received as (
    select 
        addr as address,
        sum(value) as total_received
    from received_amounts,
    unnest(address_array) as addr
    group by 1
),

-- 2. Unnest inputs to find what every address spent
spent_amounts as (
    select
        input.addresses as address_array,
        input.value as value
    from historical_transactions tx,
    unnest(inputs) as input
),

flattened_spent as (
    select 
        addr as address,
        sum(value) as total_spent
    from spent_amounts,
    unnest(address_array) as addr
    group by 1
),

-- 3. Identify and isolate Coinbase addresses to exclude them
coinbase_exclusion as (
    select distinct addr as address
    from historical_transactions tx,
    unnest(inputs) as input,
    unnest(input.addresses) as addr
    where input.type = 'coinbase'
)

-- 4. Combine metrics to calculate true current balance
select
    coalesce(r.address, s.address) as crypto_address,
    coalesce(r.total_received, 0) as total_received,
    coalesce(s.total_spent, 0) as total_spent,
    (coalesce(r.total_received, 0) - coalesce(s.total_spent, 0)) as current_balance
from flattened_received r
full outer join flattened_spent s on r.address = s.address
left join coinbase_exclusion c on coalesce(r.address, s.address) = c.address
where c.address is null -- Excludes Coinbase addresses
  and (coalesce(r.total_received, 0) - coalesce(s.total_spent, 0)) > 0
order by current_balance desc
