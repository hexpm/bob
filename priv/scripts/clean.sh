#!/bin/bash

set -euox pipefail

docker system prune -af --filter "until=6h"
