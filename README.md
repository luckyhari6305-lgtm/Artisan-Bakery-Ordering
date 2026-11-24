# Artisan Bakery

A standalone bakery website for a college project. It does not connect to Supabase or require a server-side database.

## Run

Open `index.html` with VS Code Live Server or another local static-file server.

## Products and photos

- `products.js` contains 100 bakery products with INR prices and stock counts.
- Product photos use Pexels URLs, so an internet connection is needed to display them. The photos are linked, not stored in this folder. See the [Pexels license](https://www.pexels.com/license/).
- Use **Add Product** to add another item, including an optional image from your computer.

## Local-only behavior

The catalog, cart, stock changes, and orders are saved in this browser using local storage. They are not shared with other devices or customers. Checkout records a local college-project order; it does not send an order to a bakery, collect payment, or contact a server.

The old `supabase-schema.sql` and `env.example` files are not used by the website.

## Owner registration

Use **Register / Login** in the website header:

- The first account registered in this browser is assigned the `owner` role.
- Later accounts are assigned the `customer` role.
- Only owner accounts can open **Add Product**.
- Accounts and the active session are stored only in browser local storage.
