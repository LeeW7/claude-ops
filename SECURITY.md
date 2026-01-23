# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email the maintainer or use GitHub's private vulnerability reporting feature
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Security Best Practices

When using this project:

- **Never commit secrets**: Keep `service-account.json`, `repo_map.json`, and `.env` files out of version control
- **Use HTTPS**: Always use HTTPS URLs for webhooks and API endpoints
- **Rotate credentials**: Regularly rotate API keys and service account credentials
- **Limit permissions**: Use the minimum required permissions for service accounts

## Dependencies

This project uses Dependabot to monitor for vulnerable dependencies. Security updates are prioritized and applied promptly.
