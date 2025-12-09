# TROUPE-OS API

Railway-first, API-only Node.js platform built with Express and PostgreSQL.

## Overview

This is a minimal, production-ready API platform designed to run on Railway. It uses:
- **Node.js** with JavaScript (no TypeScript)
- **Express** for HTTP routing
- **PostgreSQL** for database
- **Environment variables** for all configuration

## Prerequisites

- Node.js (v14 or higher)
- PostgreSQL database (provided by Railway or local)

## Environment Variables

Required environment variables:

```
PORT=3000                          # Port for the server (Railway sets this automatically)
DATABASE_URL=postgresql://...      # PostgreSQL connection string
NODE_ENV=production                # Environment (optional)
```

## Installation

```bash
npm install
```

## Running Locally

1. Set up your environment variables in `.env` file (not committed to git):
```
DATABASE_URL=postgresql://user:password@localhost:5432/troupeos
PORT=3000
```

2. Start the server:
```bash
npm start
```

## Railway Deployment

1. Connect your GitHub repository to Railway
2. Railway will automatically detect the Node.js project
3. Set the `DATABASE_URL` environment variable in Railway dashboard (or add PostgreSQL service)
4. Railway will automatically set the `PORT` environment variable
5. Deploy!

## API Endpoints

- `GET /` - API information and available endpoints
- `GET /health` - Health check endpoint (includes database connectivity check)
- `GET /api` - API routes (placeholder for your application logic)

## Architecture

- `server.js` - Main Express application and server setup
- `db.js` - PostgreSQL database connection pool and query helpers
- `package.json` - Node.js dependencies and scripts

## Security

- All secrets are managed via environment variables
- No hardcoded credentials
- SSL enabled for database connections in production
- Input validation via Express middleware

## Development

The application logs all requests and database queries for debugging.

To add new routes, edit `server.js` or create new route modules and require them in the main file.
