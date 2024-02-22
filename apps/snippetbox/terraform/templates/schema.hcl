schema "snippetbox" {
  charset = "utf8mb4"
  collate = "utf8mb4_unicode_ci"
}

table "snippets" {
  schema = schema.snippetbox

  column "id" {
    null           = false
    type           = int
    auto_increment = true
  }

  column "title" {
    null = false
    type = varchar(100)
  }

  column "content" {
    null = false
    type = text
  }

  column "created" {
    null = false
    type = datetime
  }

  column "expires" {
    null = false
    type = datetime
  }

  primary_key {
    columns = [column.id]
  }

  index "idx_snippets_created" {
    columns = [column.created]
  }
}

table "users" {
  schema = schema.snippetbox

  column "id" {
    null           = false
    type           = int
    auto_increment = true
  }

  column "name" {
    null = false
    type = varchar(255)
  }

  column "email" {
    null = false
    type = varchar(255)
  }

  column "hashed_password" {
    null = false
    type = char(60)
  }

  column "created" {
    null = false
    type = datetime
  }

  primary_key {
    columns = [column.id]
  }
}
