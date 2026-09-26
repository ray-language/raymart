// The payment service's own user, limited to its database (the raylang db/mongo driver always
// authenticates with SCRAM-SHA-256 against the database it connects to).
db.getSiblingDB('payments').createUser({
  user: 'payments',
  pwd: 'payments',
  roles: [{ role: 'readWrite', db: 'payments' }],
  mechanisms: ['SCRAM-SHA-256'],
});
