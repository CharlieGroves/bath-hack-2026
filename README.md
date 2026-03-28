# Bath Hack 2026

A full-stack web app with a Rails 7.2 backend and React + Vite frontend.

## Prerequisites

Install these before starting:

- [rbenv](https://github.com/rbenv/rbenv) — Ruby version manager
- [Node.js](https://nodejs.org/) (v18+) and npm
- [Redis](https://redis.io/) — `brew install redis`
- [PostgreSQL](https://www.postgresql.org/) — `brew install postgresql@16`

## Setup

### 1. Clone the repo

```bash
git clone <repo-url>
cd bath-hack-2026
```

### 2. Backend (Rails)

```bash
cd backend
```

**Install Ruby 3.4.4 via rbenv:**

```bash
rbenv install 3.4.4
rbenv local 3.4.4
ruby -v  # should show 3.4.4
```

**Install gems:**

```bash
gem install bundler
bundle install
```

**Set up Tailwind CSS:**

```bash
bin/rails tailwindcss:install
```

**Set up the database:**

```bash
bin/rails db:prepare
```

**Configure credentials** — ask a teammate for the `master.key` and place it at `backend/config/master.key` (it is git-ignored).

### 3. Frontend (React + Vite)

```bash
cd ../frontend
npm install
```

## Running locally

From the `backend` directory, run all services together:

```bash
bin/dev
```

This starts:

| Process | URL |
|---------|-----|
| Rails API | http://localhost:3000 |
| Vite (React frontend) | http://localhost:5173 |
| Sidekiq (background jobs) | — |
| Redis | port 6381 |
| Tailwind CSS watcher | — |

## Common issues

**Wrong Ruby version** — if you see `Your Ruby version is X.X.X, but your Gemfile specified 3.4.4`:

```bash
cd backend
rbenv local 3.4.4
ruby -v
```

**Tailwind input file missing** — if you see `Specified input file ./app/assets/tailwind/application.css does not exist`:

```bash
bin/rails tailwindcss:install
```

**Rails version mismatch** — if you see `Unknown version "7.2"`, ensure the Gemfile specifies `gem "rails", "~> 7.2.0"` and run `bundle install`.
