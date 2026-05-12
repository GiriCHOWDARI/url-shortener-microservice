# 🔗 URL Shortener Microservice

A scalable async URL shortener built with **FastAPI**, **SQLite** (or **PostgreSQL**), in-memory caching, rate limiting, JWT authentication, and a modern web UI.  
The project is designed to demonstrate production-ready backend engineering concepts and can be easily extended with Redis, PostgreSQL, Docker, and CI/CD.

![UI Screenshot](assets/screenshot.png)  
*Replace this with an actual screenshot of your app*

---

## ✨ Features

- ✅ **Shorten long URLs** with optional custom aliases and expiration
- ✅ **Redirect** with low latency (in‑memory cache with TTL)
- ✅ **User authentication** (register / login) with JWT tokens
- ✅ **Rate limiting** – tiered limits for anonymous and authenticated users
- ✅ **Analytics tracking** (click events stored in DB, easily extendable)
- ✅ **Modern responsive UI** (HTML + CSS + JS, served directly from FastAPI)
- ✅ **Production-ready code structure** with clear separation of concerns
- ✅ **Automatic database creation** (SQLite for quick start, PostgreSQL ready)
- ✅ **Docker & Docker Compose** for production deployment (optional)
- ✅ **Ready for CI/CD, observability, and horizontal scaling**

---

## 🧰 Tech Stack

| Component          | Technology |
|--------------------|------------|
| **Backend**        | Python 3.9+, FastAPI, Uvicorn |
| **Database**       | SQLite (dev) / PostgreSQL (prod) |
| **ORM**            | SQLAlchemy (async) |
| **Caching**        | In‑memory (dev) / Redis (prod) |
| **Auth**           | JWT (python‑jose) + bcrypt |
| **Rate Limiting**  | In‑memory / Redis‑based |
| **Frontend**       | Static HTML + CSS + Vanilla JS |
| **DevOps (optional)** | Docker, Docker Compose, GitHub Actions |

---

## 📸 Screenshots
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/cf09306d-acad-4940-ae96-44d96195ea16" />


You can add screenshots in the `assets/` folder (or any path you like) and then reference them like:

```markdown
![Homepage](assets/screenshot1.png)
![Shortened URL](assets/screenshot2.png)
