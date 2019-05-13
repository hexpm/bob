#!/bin/bash

set -euox pipefail

docker system prune -f --filter "until=168h"
