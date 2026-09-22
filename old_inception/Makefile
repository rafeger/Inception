# Display colors
GREEN=\033[0;32m
PURPLE=\033[1;35m
RED=\033[0;31m
NC=\033[0m

# docker-compose.yml file's path
COMPOSE_FILE=srcs/docker-compose.yml

# Default target
all: setup build up

# To create necessary directories (for volumes)
setup:
	@echo "$(GREEN)=== Setting up our data folders===${NC}"
	@mkdir -p /home/fpaulas-/data/wordpress
	@mkdir -p /home/fpaulas-/data/mariadb

# Build docker images
build:
	@echo "${GREEN}=== Build docker images ===${NC}"
	docker-compose -f $(COMPOSE_FILE) build

# Launch containers
up:
	@echo "${GREEN}=== Launch containers ===${NC}"
	docker-compose -f $(COMPOSE_FILE) up -d

# Stop containers
down:
	@echo "${GREEN}=== Stop containers (volumes preserved) ===${NC}"
	docker-compose -f $(COMPOSE_FILE) down

# Display logs
logs:
	@echo "${GREEN}=== Display of logs ===${NC}"
	docker-compose -f $(COMPOSE_FILE) logs

# Restart containers
restart:
	@echo "${GREEN}=== Restart containers ===${NC}"
	docker-compose -f $(COMPOSE_FILE) restart

# Rebuild images and launch containers
rebuild:
	@echo "${GREEN}=== Rebuild images and launch containers ===${NC}"
	docker-compose -f $(COMPOSE_FILE) down
	docker-compose -f $(COMPOSE_FILE) build
	docker-compose -f $(COMPOSE_FILE) up -d

# Stop containers and remove volumes (for debug if volumes are wrongly created)
clean:
	@echo "$(GREEN)Stopping containers and removing volumes...$(NC)"
	@docker-compose -f $(COMPOSE_FILE) down -v
	@echo "$(PURPLE)Containers and volumes removed$(NC)"

# Full cleanup for another start (useful for debug too)
fclean: clean
	@echo "$(GREEN)Removing data directories...$(NC)"
	@sudo rm -rf /home/fpaulas-/data
	@echo "$(GREEN)Cleaning Docker system...$(NC)"
	@docker system prune -a -f --volumes
	@docker builder prune -a -f
	@echo "$(PURPLE)Full cleanup complete$(NC)"

# Execute a shell inside a specific container
exec-%:
	@echo "${GREEN}=== Execute a shell inside a specific container $* ===${NC}"
	docker-compose -f $(COMPOSE_FILE) exec $* sh

# Display 10 last comments of Wordpress
# SHOW TABLES; to see data tables
# Describe wp_comments; to see wp_comments (datatable) content
wp-comments:
	@echo "${GREEN}=== 10 derniers commentaires WordPress ===${NC}"
	docker exec -i mariadb mysql -u root -p$$DB_ROOT_PASSWORD wordpress -e "\
SELECT comment_ID, comment_post_ID, comment_author, comment_date, comment_content \
FROM wp_comments \
ORDER BY comment_date DESC \
LIMIT 10;"

.PHONY: all setup build up down down-full logs restart rebuild exec-%
