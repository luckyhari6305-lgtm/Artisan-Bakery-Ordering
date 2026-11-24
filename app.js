const storageKey="artisan-bakery-local-v1";
const authStorageKey="artisan-bakery-auth-v1";
const authState=JSON.parse(localStorage.getItem(authStorageKey)||"null")||{users:[],session:null};
const categories=["Cakes","Pastries","Cookies","Breads","Donuts","Cupcakes","Chocolates","Other Bakery Items"];
const savedState=JSON.parse(localStorage.getItem(storageKey)||"null");
const catalogProducts=Array.isArray(window.ARTISAN_PRODUCTS)?window.ARTISAN_PRODUCTS:[];
const savedProducts=Array.isArray(savedState?.products)?savedState.products:null;
const mergedProducts=savedProducts
  ?[...savedProducts,...catalogProducts.filter(product=>!savedProducts.some(savedProduct=>savedProduct.id===product.id))]
  :catalogProducts.map(product=>({...product}));
const state={
  route:"home",
  products:mergedProducts,
  cart:savedState?.cart||[],
  orders:savedState?.orders||[]
};
const app=document.querySelector("#app");
let orderInProgress=false;

const money=value=>`₹${Number(value||0).toLocaleString("en-IN")}`;
const escapeHtml=(value="")=>String(value).replace(/[&<>"']/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[char]));

function toast(message){
  const element=document.createElement("div");
  element.className="toast";
  element.textContent=message;
  document.querySelector("#toastRoot").appendChild(element);
  setTimeout(()=>element.remove(),3500);
}
function saveState(next){
  const updated={products:next.products||state.products,cart:next.cart||state.cart,orders:next.orders||state.orders};
  try{
    localStorage.setItem(storageKey,JSON.stringify(updated));
    Object.assign(state,updated);
    document.querySelector("#cartCount").textContent=state.cart.reduce((count,item)=>count+item.quantity,0);
    return true;
  }catch(error){
    toast("Could not save this change in browser storage: "+error.message);
    return false;
  }
}
function pageShell(content){app.innerHTML=content}
function productCard(product){
  const inStock=Number(product.stock_quantity)>0;
  return `<article class="product-card">
    <div class="product-image"><img src="${escapeHtml(product.image_url||"")}" alt="${escapeHtml(product.name)}" loading="lazy">${!inStock?'<span class="badge stock">OUT OF STOCK</span>':""}</div>
    <div class="product-info"><h3>${escapeHtml(product.name)}</h3><p>${escapeHtml(product.description)}</p><div class="price-row"><span class="price">${money(product.price)}</span><span class="category">${escapeHtml(product.category)}</span></div>
    <button class="primary-button" ${inStock?"":"disabled"} onclick="addToCart('${escapeHtml(product.id)}')">${inStock?"Add to Cart":"Out of Stock"}</button></div>
  </article>`;
}
function renderHome(){
  pageShell(`<section class="hero"><div class="hero-content"><span class="eyebrow">Freshly baked every day</span><h1>Made with love,<br>served with joy.</h1><p>Discover handcrafted breads, cakes and sweet moments made from carefully chosen ingredients.</p><div class="hero-actions"><button class="primary-button" data-route="products">Shop Our Bakes</button><button class="secondary-button" data-route="about">Our Story</button></div></div></section>
  <section class="feature-strip"><div class="feature"><strong>Fresh Daily</strong><span>Baked every morning</span></div><div class="feature"><strong>Made by Hand</strong><span>Traditional artisan craft</span></div><div class="feature"><strong>Local Ingredients</strong><span>Quality you can taste</span></div></section>
  <section class="page"><div class="section-heading"><span class="eyebrow">Customer favourites</span><h1>Our Fresh Selections</h1><p>A little something for every craving.</p></div><div class="product-grid">${state.products.slice(0,8).map(productCard).join("")}</div></section>`);
}
function renderProducts(){
  pageShell(`<section class="page"><div class="section-heading"><span class="eyebrow">Our bakery</span><h1>Fresh From the Oven</h1><p>Explore our collection of ${state.products.length} bakery favourites.</p></div><div class="toolbar"><input id="productSearch" class="search-input" placeholder="Search bakery items..." oninput="filterProducts()"><select id="categoryFilter" onchange="filterProducts()"><option value="">All Categories</option>${categories.map(category=>`<option>${category}</option>`).join("")}</select></div><div id="productGrid" class="product-grid">${state.products.map(productCard).join("")}</div></section>`);
}
function filterProducts(){
  const query=(document.querySelector("#productSearch").value||"").toLowerCase();
  const category=document.querySelector("#categoryFilter").value;
  const filtered=state.products.filter(product=>(product.name+" "+product.description).toLowerCase().includes(query)&&(!category||product.category===category));
  document.querySelector("#productGrid").innerHTML=filtered.length?filtered.map(productCard).join(""):'<div class="empty-state"><h2>No products found</h2><p>Try another search or category.</p></div>';
}
function renderAbout(){
  pageShell(`<section class="page"><div class="info-grid"><img src="https://images.unsplash.com/photo-1556740749-887f6717d7e4?auto=format&fit=crop&w=900&q=80" alt="Bakery"><div class="info-copy"><span class="eyebrow">About Artisan</span><h2>From our oven to your table</h2><p>Artisan Bakery is built around honest ingredients, traditional methods and the joy of sharing freshly baked food.</p><p>We make every batch thoughtfully, from slow-fermented breads to celebration cakes and everyday pastries.</p></div></div></section>`);
}
function renderContact(){
  pageShell(`<section class="page"><div class="section-heading"><span class="eyebrow">Get in touch</span><h1>Contact Us</h1></div><div class="contact-grid"><div class="contact-card"><h2>Visit the bakery</h2><p>Fresh bakes, warm welcomes and friendly service.</p><p><strong>Phone:</strong> +91 6305 000000</p><p><strong>Email:</strong> luckyhari6305@gmail.com</p></div><form class="contact-form" onsubmit="contactSubmit(event)"><div class="form-row"><div class="field"><label>Name</label><input required></div><div class="field"><label>Phone</label><input required></div></div><div class="field"><label>Message</label><textarea required></textarea></div><button class="primary-button">Send Message</button></form></div></section>`);
}
function contactSubmit(event){event.preventDefault();toast("This college project form does not send messages")}
function getCurrentUser(){
  return authState.users.find(user=>user.id===authState.session)?.id ? authState.users.find(user=>user.id===authState.session) : null;
}
function saveAuthState(){
  try{
    localStorage.setItem(authStorageKey,JSON.stringify(authState));
    updateHeaderAuth();
    return true;
  }catch(error){
    toast("Could not save account information: "+error.message);
    return false;
  }
}
function updateHeaderAuth(){
  const user=getCurrentUser();
  const authButton=document.querySelector("#authButton");
  const mobileAuthButton=document.querySelector("#mobileAuthButton");
  const addProductButton=document.querySelector("#addProductButton");
  if(authButton)authButton.textContent=user?`Logout (${user.fullName})`:"Register / Login";
  if(mobileAuthButton)mobileAuthButton.textContent=user?"Logout":"Register / Login";
  if(addProductButton)addProductButton.hidden=!user||user.role!=="owner";
  document.querySelectorAll(".mobile-only[data-route='add-product']").forEach(button=>{
    button.hidden=!user||user.role!=="owner";
  });
}
async function hashPassword(password){
  if(!window.crypto?.subtle)throw new Error("Secure registration is unavailable in this browser");
  const bytes=new TextEncoder().encode(password);
  const digest=await crypto.subtle.digest("SHA-256",bytes);
  return Array.from(new Uint8Array(digest)).map(byte=>byte.toString(16).padStart(2,"0")).join("");
}
function renderAuth(){
  const user=getCurrentUser();
  if(user){
    pageShell(`<section class="auth-wrap"><div class="auth-card"><span class="eyebrow">Account</span><h1>Hello, ${escapeHtml(user.fullName)}</h1><p class="auth-note">You are registered as <b>${escapeHtml(user.role)}</b>.</p><button class="primary-button" style="width:100%;margin-top:20px" onclick="logout()">Logout</button></div></section>`);
    return;
  }
  pageShell(`<section class="auth-wrap"><div class="auth-card"><span class="eyebrow">Artisan Bakery</span><h1>Register or Login</h1><div class="auth-tabs"><button id="registerTab" class="active" type="button" onclick="switchAuthTab('register')">Register</button><button id="loginTab" type="button" onclick="switchAuthTab('login')">Login</button></div><form id="authForm" onsubmit="registerAccount(event)"><div class="field"><label>Full name</label><input name="fullName" required></div><div class="field"><label>Email</label><input name="email" type="email" required></div><div class="field"><label>Password</label><input name="password" type="password" minlength="6" required></div><button class="primary-button">Create Account</button></form></div></section>`);
}
function switchAuthTab(mode){
  document.querySelector("#registerTab").classList.toggle("active",mode==="register");
  document.querySelector("#loginTab").classList.toggle("active",mode==="login");
  const form=document.querySelector("#authForm");
  if(mode==="login"){
    form.innerHTML=`<div class="field"><label>Email</label><input name="email" type="email" required></div><div class="field"><label>Password</label><input name="password" type="password" minlength="6" required></div><button class="primary-button">Login</button>`;
    form.onsubmit=loginAccount;
  }else{
    form.innerHTML=`<div class="field"><label>Full name</label><input name="fullName" required></div><div class="field"><label>Email</label><input name="email" type="email" required></div><div class="field"><label>Password</label><input name="password" type="password" minlength="6" required></div><button class="primary-button">Create Account</button>`;
    form.onsubmit=registerAccount;
  }
}
async function registerAccount(event){
  event.preventDefault();
  const form=new FormData(event.target);
  const fullName=String(form.get("fullName")||"").trim();
  const email=String(form.get("email")||"").trim().toLowerCase();
  const password=String(form.get("password")||"");
  if(!fullName||!email||password.length<6)return toast("Enter a name, email, and password of at least 6 characters");
  if(authState.users.some(user=>user.email===email))return toast("An account with this email already exists");
  let passwordHash;
  try{passwordHash=await hashPassword(password)}catch(error){return toast(error.message)}
  const role=authState.users.length===0?"owner":"customer";
  const user={id:`local-user-${Date.now()}-${Math.random().toString(36).slice(2,8)}`,fullName,email,passwordHash,role};
  authState.users.push(user);
  authState.session=user.id;
  if(saveAuthState()){toast(role==="owner"?"Account created: you are the owner":"Account created");navigate("home")}
}
async function loginAccount(event){
  event.preventDefault();
  const form=new FormData(event.target);
  const email=String(form.get("email")||"").trim().toLowerCase();
  const password=String(form.get("password")||"");
  let passwordHash;
  try{passwordHash=await hashPassword(password)}catch(error){return toast(error.message)}
  const user=authState.users.find(entry=>entry.email===email&&entry.passwordHash===passwordHash);
  if(!user)return toast("Invalid email or password");
  authState.session=user.id;
  if(saveAuthState()){toast("Logged in successfully");navigate("home")}
}
function logout(){
  authState.session=null;
  if(saveAuthState()){toast("Logged out");navigate("home")}
}
function addToCart(id){
  const product=state.products.find(item=>item.id===id);
  if(!product||product.stock_quantity<1)return;
  const current=state.cart.find(item=>item.id===id);
  if(current&&current.quantity>=product.stock_quantity){toast("Maximum available stock reached");return}
  const cart=current?state.cart.map(item=>item.id===id?{...item,quantity:item.quantity+1}:item):[...state.cart,{...product,quantity:1}];
  if(saveState({cart}))toast(`${product.name} added to cart`);
}
function changeQty(id,delta){
  const product=state.products.find(item=>item.id===id);
  const cart=state.cart.map(item=>{
    if(item.id!==id)return item;
    return {...item,quantity:Math.max(1,Math.min(product?.stock_quantity||item.quantity,item.quantity+delta))};
  });
  if(saveState({cart}))renderCart();
}
function removeCart(id){
  if(saveState({cart:state.cart.filter(item=>item.id!==id)}))renderCart();
}
function renderCart(){
  if(!state.cart.length){pageShell(`<section class="page"><div class="empty-state"><h2>Your cart is empty</h2><p>Add a few fresh favourites to begin.</p><button class="primary-button" data-route="products">Browse Products</button></div></section>`);return}
  const total=state.cart.reduce((sum,item)=>sum+item.price*item.quantity,0);
  pageShell(`<section class="page"><div class="section-heading"><h1>Your Shopping Cart</h1></div><div class="cart-layout"><div>${state.cart.map(item=>`<div class="cart-item"><img src="${escapeHtml(item.image_url)}" alt="${escapeHtml(item.name)}"><div><h3>${escapeHtml(item.name)}</h3><p>${money(item.price)} each</p><button class="remove-button" onclick="removeCart('${escapeHtml(item.id)}')">Remove</button></div><div class="quantity"><button onclick="changeQty('${escapeHtml(item.id)}',-1)" aria-label="Decrease quantity">−</button><span>${item.quantity}</span><button onclick="changeQty('${escapeHtml(item.id)}',1)" aria-label="Increase quantity">+</button></div></div>`).join("")}</div><aside class="checkout-summary"><h2>Order Summary</h2><div class="summary-row"><span>Subtotal</span><b>${money(total)}</b></div><div class="summary-row"><span>Delivery</span><b>Calculated at checkout</b></div><div class="summary-row total"><span>Total</span><span>${money(total)}</span></div><button class="primary-button" data-route="checkout">Proceed to Checkout</button></aside></div></section>`);
}
function renderAddProduct(){
  pageShell(`<section class="page"><div class="section-heading"><span class="eyebrow">Bakery inventory</span><h1>Add a Product</h1><p>Products and orders are saved in this browser for this college project.</p></div><div class="panel"><form class="admin-form" onsubmit="saveProduct(event)"><div class="field full"><label>Product name</label><input name="name" required></div><div class="field full"><label>Description</label><textarea name="description" required></textarea></div><div class="field full"><label>Product image (optional)</label><input name="image" type="file" accept="image/*" onchange="previewImage(event)"><div class="image-preview" id="imagePreview">Choose an image</div></div><div class="field"><label>Cost (₹)</label><input name="price" type="number" min="0" step="0.01" required></div><div class="field"><label>Category</label><select name="category">${categories.map(category=>`<option>${category}</option>`).join("")}</select></div><div class="field"><label>Stock quantity</label><input name="stock_quantity" type="number" min="0" step="1" required></div><div class="full"><button class="primary-button">Add Product</button><button class="secondary-button" type="button" data-route="products">View Products</button></div></form></div></section>`);
}
function previewImage(event){
  const file=event.target.files[0];
  if(!file)return;
  const reader=new FileReader();
  reader.onload=()=>{const preview=document.querySelector("#imagePreview");if(!preview)return;const image=new Image();image.alt="Product preview";image.src=String(reader.result);preview.replaceChildren(image)};
  reader.onerror=()=>toast("Could not read the selected image");
  reader.readAsDataURL(file);
}
function compressImage(file){
  return new Promise((resolve,reject)=>{
    const reader=new FileReader();
    reader.onerror=()=>reject(new Error("Could not read the selected image"));
    reader.onload=()=>{
      const image=new Image();
      image.onerror=()=>reject(new Error("The selected file is not a usable image"));
      image.onload=()=>{
        const scale=Math.min(1,900/Math.max(image.width,image.height));
        const canvas=document.createElement("canvas");
        canvas.width=Math.max(1,Math.round(image.width*scale));
        canvas.height=Math.max(1,Math.round(image.height*scale));
        const context=canvas.getContext("2d");
        if(!context){reject(new Error("Image processing is unavailable in this browser"));return}
        context.fillStyle="#ffffff";
        context.fillRect(0,0,canvas.width,canvas.height);
        context.drawImage(image,0,0,canvas.width,canvas.height);
        resolve(canvas.toDataURL("image/jpeg",0.8));
      };
      image.src=String(reader.result);
    };
    reader.readAsDataURL(file);
  });
}
async function saveProduct(event){
  event.preventDefault();
  const form=new FormData(event.target);
  const name=String(form.get("name")||"").trim();
  const description=String(form.get("description")||"").trim();
  const price=Number(form.get("price"));
  const stock=Number(form.get("stock_quantity"));
  const category=String(form.get("category")||"");
  if(!name||!description||!categories.includes(category)||!Number.isFinite(price)||price<0||!Number.isInteger(stock)||stock<0)return toast("Enter a valid product name, description, cost, category, and stock quantity");
  let imageUrl="";
  const file=form.get("image");
  if(file&&file.size){
    if(!file.type.startsWith("image/"))return toast("Choose an image file");
    try{imageUrl=await compressImage(file)}catch(error){return toast(error.message)}
  }
  const product={id:`local-${Date.now()}-${Math.random().toString(36).slice(2,8)}`,name,description,price,category,stock_quantity:stock,image_url:imageUrl||state.products[0]?.image_url||"",created_at:new Date().toISOString()};
  if(saveState({products:[product,...state.products]})){toast("Product added");navigate("products")}
}
function renderCheckout(){
  if(!state.cart.length){navigate("cart");return}
  const total=state.cart.reduce((sum,item)=>sum+item.price*item.quantity,0);
  pageShell(`<section class="page"><div class="section-heading"><h1>Checkout</h1></div><form class="checkout-layout" onsubmit="placeOrder(event)"><div class="contact-form"><div class="form-row"><div class="field"><label>Customer name</label><input name="customer_name" required></div><div class="field"><label>Phone number</label><input name="phone" required></div></div><div class="field"><label>Fulfilment preference</label><select name="fulfilment" onchange="changeFulfilment(this.value)"><option>Delivery</option><option>Pickup</option></select></div><div class="field"><label id="addressLabel">Delivery address</label><textarea id="addressField" name="address" required></textarea></div><div class="field"><label>Order notes</label><textarea name="notes"></textarea></div></div><aside class="checkout-summary"><h2>Final Summary</h2>${state.cart.map(item=>`<div class="summary-row"><span>${escapeHtml(item.name)} × ${item.quantity}</span><b>${money(item.price*item.quantity)}</b></div>`).join("")}<div class="summary-row total"><span>Total</span><span>${money(total)}</span></div><button class="primary-button">Place Order</button></aside></form></section>`);
}
function changeFulfilment(value){
  const field=document.querySelector("#addressField");
  const label=document.querySelector("#addressLabel");
  if(!field||!label)return;
  if(value==="Pickup"){field.removeAttribute("required");field.value="";field.placeholder="No address required for pickup";label.textContent="Pickup location / contact notes"}
  else{field.setAttribute("required","");field.placeholder="";label.textContent="Delivery address"}
}
function placeOrder(event){
  event.preventDefault();
  if(orderInProgress)return;
  if(state.cart.some(item=>item.quantity<1))return toast("Invalid cart quantity");
  const form=new FormData(event.target);
  const fulfilment=String(form.get("fulfilment")||"");
  const address=String(form.get("address")||"").trim();
  if(fulfilment==="Delivery"&&!address)return toast("Delivery address is required");
  for(const item of state.cart){
    const product=state.products.find(entry=>entry.id===item.id);
    if(!product||product.stock_quantity<item.quantity)return toast(`Insufficient stock for ${item.name}`);
  }
  orderInProgress=true;
  const items=state.cart.map(item=>({product_id:item.id,product_name:item.name,unit_price:item.price,quantity:item.quantity,line_total:item.price*item.quantity}));
  const total=items.reduce((sum,item)=>sum+item.line_total,0);
  const order={order_number:`AB-${Date.now().toString().slice(-8)}`,customer_name:String(form.get("customer_name")||"").trim(),phone:String(form.get("phone")||"").trim(),fulfilment,address,notes:String(form.get("notes")||"").trim(),total,status:"Received",created_at:new Date().toISOString(),order_items:items};
  const products=state.products.map(product=>{
    const ordered=state.cart.find(item=>item.id===product.id);
    return ordered?{...product,stock_quantity:product.stock_quantity-ordered.quantity}:product;
  });
  const saved=saveState({products,orders:[order,...state.orders],cart:[]});
  orderInProgress=false;
  if(saved)renderSuccess(order);
}
function renderSuccess(order){
  pageShell(`<section class="page"><div class="empty-state"><span class="eyebrow">Thank you</span><h2>Your order has been recorded</h2><p>Order <b>${escapeHtml(order.order_number)}</b></p><p>This college-project order is saved in this browser only.</p><div style="max-width:500px;margin:20px auto;text-align:left">${order.order_items.map(item=>`<div class="summary-row"><span>${escapeHtml(item.product_name)} × ${item.quantity}</span><b>${money(item.line_total)}</b></div>`).join("")}<div class="summary-row total"><span>Total</span><span>${money(order.total)}</span></div></div><button class="primary-button" data-route="orders">View My Orders</button></div></section>`);
}
function renderOrders(){
  if(!state.orders.length){pageShell(`<section class="page"><div class="empty-state"><h2>No orders yet</h2><p>Orders placed in this browser will appear here.</p><button class="primary-button" data-route="products">Start Shopping</button></div></section>`);return}
  pageShell(`<section class="page"><div class="section-heading"><h1>My Orders</h1><p>Order history saved in this browser.</p></div><div class="orders-list">${state.orders.map(order=>`<article class="order-card"><div class="order-head"><h3>${escapeHtml(order.order_number)}</h3><span class="status">${escapeHtml(order.status)}</span></div><div class="order-items">${order.order_items.map(item=>`<div class="order-line"><span>${escapeHtml(item.product_name)} × ${item.quantity}</span><b>${money(item.line_total)}</b></div>`).join("")}</div><div class="order-foot"><div><small>${new Date(order.created_at).toLocaleString()}</small><br><strong>${money(order.total)}</strong></div></div></article>`).join("")}</div></section>`);
}
function navigate(route){
  const allowed=["home","products","about","contact","cart","checkout","orders","add-product","auth"];
  if(!allowed.includes(route))route="home";
  if(route==="add-product"){
    const user=getCurrentUser();
    if(!user||user.role!=="owner"){toast("Owner access required");route="auth"}
  }
  state.route=route;
  window.scrollTo({top:0,behavior:"smooth"});
  document.querySelector(".main-nav")?.classList.remove("open");
  if(location.hash.slice(1)!==route)history.pushState({route},"",`#${route}`);
  if(route==="home")renderHome();
  else if(route==="products")renderProducts();
  else if(route==="about")renderAbout();
  else if(route==="contact")renderContact();
  else if(route==="cart")renderCart();
  else if(route==="checkout")renderCheckout();
  else if(route==="orders")renderOrders();
  else if(route==="auth")renderAuth();
  else renderAddProduct();
}

document.addEventListener("click",event=>{const route=event.target.closest("[data-route]")?.dataset.route;if(route)navigate(route)});
document.querySelector("#menuButton").addEventListener("click",()=>document.querySelector(".main-nav").classList.toggle("open"));
window.addEventListener("popstate",()=>navigate(location.hash.slice(1)||"home"));
if(!savedState)saveState({});
else if(savedProducts&&mergedProducts.length>savedProducts.length)saveState({products:mergedProducts});
document.querySelector("#cartCount").textContent=state.cart.reduce((count,item)=>count+item.quantity,0);
document.querySelector("#year").textContent=new Date().getFullYear();
updateHeaderAuth();
const initialRoute=new URL(location.href).searchParams.get("route")||location.hash.slice(1)||"home";
navigate(initialRoute);
