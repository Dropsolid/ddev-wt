# Project Instructions for Claude Code

## Code Style & Standards

### Drupal Coding Standards
- Follow [Drupal Coding Standards](https://www.drupal.org/docs/develop/standards)
- Use 2 spaces for indentation (no tabs)
- Maximum line length: 80 characters for code, no limit for comments
- Use meaningful variable names: `$user_profile` not `$up`
- Class names: PascalCase (`UserProfileController`)
- Functions/methods: camelCase (`getUserProfile()`)
- Constants: UPPER_SNAKE_CASE (`USER_PROFILE_CACHE_TTL`)

### PHPDoc Comments
Always add PHPDoc blocks for:
```php
/**
 * Brief description of the function.
 *
 * Longer description if needed, explaining what the function does,
 * any important details, or edge cases.
 *
 * @param string $param_name
 *   Description of the parameter.
 * @param int $another_param
 *   Description of another parameter.
 *
 * @return array
 *   Description of the return value.
 *
 * @throws \Exception
 *   When something goes wrong.
 */
public function myFunction($param_name, $another_param) {
  // Implementation
}
```

### Best Practices
- Keep functions focused and small (< 50 lines ideally)
- One responsibility per function
- Avoid deep nesting (max 3 levels)
- Use early returns to reduce nesting
- Prefer dependency injection over global functions
- Use type hints for parameters and return values

## Testing

### Running Tests
```bash
# Run all tests
ddev exec phpunit

# Run specific test class
ddev exec phpunit path/to/TestClass.php

# Run with coverage
ddev exec phpunit --coverage-text

# Run tests matching pattern
ddev exec phpunit --filter testMethodName
```

### Writing Tests
- Place tests in `tests/src/` directory
- Follow naming: `ClassNameTest.php` for `ClassName.php`
- Use descriptive test method names: `testUserCanLoginWithValidCredentials()`
- Always test edge cases and error conditions
- Mock external dependencies

### Before Committing
```bash
# Run all checks
ddev exec phpunit
ddev exec phpcs --standard=Drupal web/modules/custom
ddev exec phpstan analyze
```

## Common Development Tasks

### Adding a New Module
```bash
# Generate module scaffold
ddev drush generate module

# Or manually create structure:
# web/modules/custom/my_module/
# ├── my_module.info.yml
# ├── my_module.module
# └── src/

# Install the module
ddev composer require drupal/my_module  # if from packagist
ddev drush en my_module -y
ddev drush cr
```

### Working with Configuration
```bash
# Export configuration
ddev drush cex -y

# Import configuration
ddev drush cim -y

# Check configuration status
ddev drush config:status
```

### Database Operations
```bash
# Run database updates
ddev drush updb -y

# Clear cache
ddev drush cr

# Access database
ddev mysql

# Export database
ddev export-db --file=backup.sql.gz

# Import database  
ddev import-db --file=backup.sql.gz
```

### Debugging
```bash
# View logs
ddev logs
ddev logs -f  # follow logs

# Access container
ddev ssh

# Run Drush commands
ddev drush <command>

# Check status
ddev describe
```

## Git Workflow

### Committing Changes
```bash
# Check what you're committing
ddev wt-status
git status

# Stage changes
git add path/to/file

# Commit with meaningful message
git commit -m "feat: add user profile export functionality

- Add CSV export button to user profile page
- Implement export service with proper permissions
- Add tests for export functionality"

# Push to remote (first time)
git push -u origin <branch-name>

# Subsequent pushes
git push
```

### Commit Message Format
Follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` new feature
- `fix:` bug fix
- `refactor:` code restructuring
- `test:` adding/updating tests
- `docs:` documentation changes
- `chore:` maintenance tasks

## Safety Checks

### Before Making Changes
1. Verify you're in the correct worktree: `pwd`
2. Check current branch: `git branch --show-current`
3. Ensure DDEV is running: `ddev describe`
4. Check for uncommitted changes: `git status`

### Before Pushing
1. Run tests: `ddev exec phpunit`
2. Check code standards: `ddev exec phpcs --standard=Drupal web/modules/custom`
3. Review changes: `git diff`
4. Check all worktrees: `ddev wt-status`

### Common Pitfalls to Avoid
- ❌ Don't commit directly to `main` or `develop`
- ❌ Don't commit vendor/ or node_modules/
- ❌ Don't commit .env files or credentials
- ❌ Don't push untested code
- ❌ Don't force push to shared branches
- ✅ Always work in a feature branch
- ✅ Always run tests before committing
- ✅ Always pull before starting new work
- ✅ Always use meaningful commit messages

## Project-Specific Notes

### Directory Structure
```
project/
├── web/                    # Drupal root
│   ├── modules/
│   │   └── custom/        # Custom modules
│   ├── themes/
│   │   └── custom/        # Custom themes
│   └── sites/
│       └── default/
├── config/                # Configuration management
├── vendor/                # Composer dependencies (gitignored)
├── .ddev/                 # DDEV configuration
└── composer.json          # PHP dependencies
```

### Key Files
- `composer.json` - PHP dependencies
- `config/sync/` - Exported Drupal configuration
- `.ddev/config.yaml` - DDEV settings (symlinked)
- `.ddev/config.local.yaml` - Worktree-specific DDEV name

### Environment Variables
Access via `$_ENV` or `getenv()`:
- `DDEV_PRIMARY_URL` - Current site URL
- `DDEV_HOSTNAME` - Current hostname
- `DDEV_PROJECT` - DDEV project name

## Getting Help

### Documentation
- Drupal API: https://api.drupal.org
- DDEV Docs: https://ddev.readthedocs.io
- Project README: See main project README.md

### Commands Reference
```bash
ddev wt-sync          # Sync DB from remote
ddev wt-status        # Check all worktrees
ddev snapshot         # Backup current DB (built-in DDEV command)
ddev exec phpunit     # Run tests
```

### Troubleshooting
If something goes wrong:
1. Check DDEV status: `ddev describe`
2. Check logs: `ddev logs`
3. Try restarting: `ddev restart`
4. Clear cache: `ddev drush cr`
5. Check git status: `git status`
