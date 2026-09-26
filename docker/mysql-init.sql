-- The raylang db/mysql driver speaks caching_sha2_password only on its fast path (a warm
-- server cache) or over TLS; the orders user authenticates with mysql_native_password instead.
ALTER USER 'orders'@'%' IDENTIFIED WITH mysql_native_password BY 'orders';
