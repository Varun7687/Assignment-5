# Assignment 5 — Application Source Notes

## Source material

The public Assignment 4 repository was used as the application reference:

* [Assignment 4 app.py](https://github.com/Varun7687/Assignment-4/blob/main/app.py)
* [Assignment 4 requirements.txt](https://github.com/Varun7687/Assignment-4/blob/main/requirements.txt)
* [Assignment 4 templates/index.html](https://github.com/Varun7687/Assignment-4/blob/main/templates/index.html)

The direct file pages were readable. The repository-root reader failed. The indexed app view did not preserve Python indentation and split two quoted error messages across lines. Consequently, this package's Python file is a syntax-checked adaptation based on the recovered routes, query/field contracts, and messages, not an exact raw export. The template was extracted from the indexed HTML source, excluding GitHub page navigation and footer. An exact upstream commit hash was not recovered or pinned.

## Preserved application contract

* Flask routes: `GET /`, `POST /items`, `GET /health`.
* Template: `templates/index.html`, using the `items` collection and `display_time` filter.
* Database: `inventory`, table `items`.
* Fields: `id`, `item_name`, `sku`, `quantity`, `warehouse_location`, `last_updated`.
* Form fields: `item_name`, `sku`, `quantity`, `warehouse_location`.
* Dependency versions retained from Assignment 4: Flask 3.1.0, PyMySQL[rsa] 1.1.1, Gunicorn 23.0.0; boto3 added for AWS secret retrieval.

The template retains the original Northwind inventory branding; the surrounding infrastructure keeps its existing Bluefin names for state compatibility.

## Assignment 5 adaptations

* Replaced direct DB credential environment inputs with `AWS_DEFAULT_REGION` and `DB_SECRET_ARN`. The secret holds host/port/username/password/database.
* Added TLS CA verification with the documented private-CNAME hostname-verification limitation.
* Replaced the public default Flask signing key with an optional private `APP_SECRET_KEY` or a deterministic SHA-256 derivation from the generated app database password and a fixed context label. Changing that database password invalidates sessions after restart.
* Added length bounds and integer bounds consistent with the schema, and parameterized inserts.
* Limited the inventory display to 200 rows; the template item counter reflects displayed rows, not an unlimited count.
* Changed health from a connectivity-only query to an `items` schema query; returns 503 until the table is accessible.
* Added a controlled 503 for initial inventory-read failures and avoided logging SQL exception details on insert failure.
* Integrated the separate template and root requirements into Terraform user data. No runtime GitHub clone or token is needed.
* Changed the earlier reconstructed starter bootstrap table from `inventory` to Assignment 4's `items` contract. Existing starter data is not automatically copied or deleted.

This lab app has no authentication or CSRF protection and is not production-ready. Review dependency advisories and runtime behavior before any approved deployment. Mocked tests are not a substitute for installing the dependencies and exercising real Flask/Jinja/MySQL.
