# JLOODNA — Magazin global en Haïti

Boutique en ligne réelle : HTML/CSS/JS modulaire (sans framework) + Supabase (PostgreSQL, Auth, Storage, Realtime, RLS) + Vercel.
Logos : `assets/logo/original/` contient vos deux images **telles que fournies**. Le site affiche `logo.webp` (même image, marges blanches rognées, rien d’autre modifié) et les icônes/favicon sont dérivés de la 2ᵉ image.

## Structure
`*.html` pages client · `admin/` Admin Center (une seule application, sections par `#hash`) · `js/` modules · `admin/js/` modules admin · `supabase/` SQL · `api/` fonctions Vercel (email, sitemap) · `scripts/build-config.js` build.

## 1. Installation locale
```bash
cp .env.example .env     # puis remplir VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY
export $(grep -v '^#' .env | xargs) && npm run dev   # http://localhost:3000
```
Le build génère `js/config.js` (valeurs publiques seulement) et copie le site dans `dist/` (les dossiers `supabase/` et `scripts/` ne sont jamais publiés).

## 2. Créer le projet Supabase
supabase.com → New project → région proche (ex. US East) → noter **Project URL** et **anon public key** (Settings → API). N’utilisez **jamais** la clé `service_role` dans ce projet.

## 3–5. Base de données, policies, storage
SQL Editor, exécuter **dans l’ordre** : `supabase/schema.sql` → `supabase/policies.sql` → (optionnel) `supabase/seed.sql`.
Le bucket public `product-images` (5 Mo, JPG/PNG/WebP) et ses règles d’écriture (réservées aux rôles autorisés) sont créés par `policies.sql`.
Supprimer la démo : `delete from products where sku like 'DEMO-%'; delete from categories where slug like 'demo-%';`

## 6. Authentication
Authentication → Providers → Email activé, **Confirm email activé**. URL Configuration : Site URL `https://www.jloodna.com`, Redirect URLs `https://www.jloodna.com/**` et `http://localhost:3000/**`.
Emails d’auth (inscription, mot de passe oublié) : Authentication → SMTP Settings → utiliser Resend (host `smtp.resend.com`, port 465, user `resend`, mot de passe = clé API).

## 7. Realtime
Activé par `schema.sql` (tables notifications, orders, products, inventory, messages). Vérifier : Database → Replication → `supabase_realtime`.

## 8. Variables d’environnement
| Variable | Où | Rôle |
|---|---|---|
| `VITE_SUPABASE_URL` | Vercel | URL du projet (publique) |
| `VITE_SUPABASE_ANON_KEY` | Vercel | clé anon (publique, protégée par RLS) |
| `VITE_SITE_URL` | Vercel | `https://www.jloodna.com` |
| `RESEND_API_KEY` | Vercel (serveur) | envoi des emails de commande |
| `EMAIL_FROM` | Vercel (serveur) | ex. `JLOODNA <commandes@jloodna.com>` (domaine vérifié dans Resend) |
| `ADMIN_EMAIL` | Vercel (serveur) | reçoit les nouvelles commandes |
| `MONCASH_*`, `NATCASH_API_KEY`, `PAYPAL_*`, `STRIPE_SECRET_KEY` | Vercel (serveur) | réservées aux futures passerelles |

## 9. Créer le compte admin
1. Allez sur `/register` et créez un compte avec **jloodna@gmail.com** (mot de passe de votre choix : jamais dans le code).
2. Cliquez le lien de confirmation reçu par email.
3. Le premier compte confirmé avec cet email devient automatiquement `SUPER_ADMIN` (un compte non confirmé ne reçoit jamais de droits).
4. Connectez-vous sur `/admin`. Ajoutez ensuite des collaborateurs dans **Paramètres → Équipe et rôles** (ils doivent d’abord s’inscrire).
Rôles : SUPER_ADMIN (tout) · ADMIN · MANAGER · EDITOR (produits, catégories) · SUPPORT (commandes, clients, messages). Permissions modifiables dans la table `admin_permissions`.

## 10. Déploiement GitHub + Vercel
```bash
git init && git add . && git commit -m "JLOODNA" && git branch -M main
git remote add origin https://github.com/<vous>/jloodna.git && git push -u origin main
```
Vercel → Add New Project → importer le dépôt → Framework « Other » (le `vercel.json` fixe build `npm run build` et sortie `dist`) → ajouter les variables ci-dessus → Deploy.

## 11. Domaine jloodna.com
Vercel → Project → Domains : ajouter `www.jloodna.com` (principal) et `jloodna.com`. Chez votre registrar : `CNAME www → cname.vercel-dns.com` et `A @ → 76.76.21.21` (ou valeurs affichées par Vercel). `jloodna.com` est redirigé en 301 vers `www` (voir `vercel.json`). HTTPS automatique.

## 12. Emails
Créer un compte Resend, vérifier le domaine `jloodna.com`, créer une clé API → `RESEND_API_KEY`. Sans clé, la boutique fonctionne normalement et aucun email n’est envoyé. Envoyés : confirmation de commande (client), nouvelle commande (admin), changement de statut (client). Alertes stock : notifications temps réel dans l’admin.

## 13. Paiements
Aujourd’hui **seul le paiement à la livraison est actif** — aucun paiement n’est simulé. `settings.payment_methods` (table `settings`) liste MonCash, NatCash, carte et PayPal **désactivés**. Pour en ajouter un : créer une fonction `api/pay-<nom>.js` qui crée la transaction avec les clés privées, vérifie le paiement côté serveur, puis marque `orders.payment_status='paid'` ; ensuite activer la méthode dans la table `settings`. La fonction SQL `create_order` refuse toute méthode désactivée.

## Sécurité (checklist)
- [x] Aucune clé secrète dans le frontend (le build refuse une clé `service_role`)
- [x] RLS activé et forcé sur toutes les tables ; droits de table minimaux
- [x] Commandes créées uniquement par la fonction serveur `create_order` (prix, stock, coupon recalculés en base)
- [x] Statuts et stock modifiables uniquement par RPC avec permission ; notifications créées par le serveur seulement
- [x] Client isolé : commandes, adresses, panier, notifications, profil = les siens uniquement
- [x] Admin protégé (rôle vérifié par la base, pas seulement par l’interface) ; audit logs automatiques
- [x] XSS : toutes les données affichées sont échappées ; CSP stricte dans `vercel.json`
- [x] Upload : JPG/PNG/WebP, 5 Mo, contrôlé côté navigateur **et** par le bucket
- [ ] À faire par vous : activer la 2FA sur Supabase/GitHub/Vercel, activer « Confirm email », surveiller les logs Supabase
- [ ] Limitation de débit : activer les rate limits Auth dans Supabase (Authentication → Rate Limits)

## Tests réalisés / à faire
Réalisé ici : exécution complète de `schema.sql`, `policies.sql`, `seed.sql` sur PostgreSQL 16 ; test de l’isolation client/admin, création de commande, refus de stock insuffisant, méthode de paiement désactivée, statut → notification, annulation → remise en stock, alertes de stock, audit ; vérification de syntaxe de tous les modules JS.
**Non testé ici (pas d’accès à votre projet Supabase ni à un navigateur)** : parcours dans le navigateur, Realtime en conditions réelles, upload Storage, emails. Après déploiement, parcourez la liste : inscription → commande → notification admin instantanée → changement de statut → notification client ; ajout d’un produit avec image depuis le téléphone ; tailles 320 à 1920 px.

## Choix d’architecture
Admin en une seule page (`/admin/`) avec sections plutôt que 12 fichiers HTML : un seul contrôle d’accès, navigation plus rapide sur mobile. Les adresses IP ne sont pas collectées dans les audit logs (minimisation des données).
