# API v1 Documentation - Categorization Patterns

## Authentication

All API endpoints require authentication via Bearer token in the Authorization header:

```
Authorization: Bearer YOUR_API_TOKEN
```

## Rate Limiting

The API implements rate limiting to ensure fair usage:

- **General API endpoints**: 100 requests per minute per IP
- **Categorization suggestions**: 30 requests per minute per token
- **Batch categorization**: 10 requests per minute per token
- **Pattern creation**: 20 creations per hour per token
- **Feedback submission**: 50 submissions per hour per token

Rate limit headers are included in responses:
- `X-RateLimit-Limit`: Maximum requests allowed
- `X-RateLimit-Remaining`: Requests remaining
- `X-RateLimit-Reset`: Unix timestamp when limit resets

## Endpoints

### Patterns Management

#### GET /api/v1/patterns
List all categorization patterns with pagination.

**Query Parameters:**
- `page` (integer): Page number (default: 1)
- `per_page` (integer): Items per page (default: 25, max: 100)
- `pattern_type` (string): Filter by type (merchant, keyword, description, amount_range, regex, time)
- `category_id` (integer): Filter by category
- `active` (boolean): Filter by active status
- `user_created` (boolean): Filter user-created patterns
- `min_success_rate` (float): Minimum success rate (0-1)
- `min_usage_count` (integer): Minimum usage count
- `sort_by` (string): Sort field (success_rate, usage_count, created_at, pattern_type)
- `sort_direction` (string): Sort direction (asc, desc)
- `include_metadata` (boolean): Include metadata field

**Response:**
```json
{
  "status": "success",
  "patterns": [
    {
      "id": 1,
      "pattern_type": "merchant",
      "pattern_value": "walmart",
      "confidence_weight": 2.0,
      "active": true,
      "user_created": false,
      "category": {
        "id": 5,
        "name": "Groceries",
        "color": "#10B981",
        "icon": "shopping-cart"
      },
      "statistics": {
        "usage_count": 150,
        "success_count": 135,
        "success_rate": 0.900,
        "effective_confidence": 0.850
      },
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-20T15:45:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 125,
    "per_page": 25,
    "next_page": 2,
    "prev_page": null
  }
}
```

#### GET /api/v1/patterns/:id
Get a specific pattern by ID.

**Response:**
```json
{
  "status": "success",
  "pattern": {
    "id": 1,
    "pattern_type": "merchant",
    "pattern_value": "walmart",
    "confidence_weight": 2.0,
    "active": true,
    "user_created": false,
    "category": {
      "id": 5,
      "name": "Groceries",
      "color": "#10B981",
      "icon": "shopping-cart"
    },
    "statistics": {
      "usage_count": 150,
      "success_count": 135,
      "success_rate": 0.900,
      "effective_confidence": 0.850
    },
    "metadata": {
      "source": "user_feedback",
      "created_by": "system"
    },
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-20T15:45:00Z"
  }
}
```

#### POST /api/v1/patterns
Create a new categorization pattern.

**Request Body:**
```json
{
  "pattern": {
    "pattern_type": "merchant",
    "pattern_value": "target",
    "category_id": 5,
    "confidence_weight": 1.5,
    "active": true,
    "metadata": {
      "notes": "User-defined pattern for Target stores"
    }
  }
}
```

**Response:** 201 Created
```json
{
  "status": "success",
  "pattern": {
    "id": 125,
    "pattern_type": "merchant",
    "pattern_value": "target",
    "confidence_weight": 1.5,
    "active": true,
    "user_created": true,
    "category": {
      "id": 5,
      "name": "Groceries"
    }
  }
}
```

#### PATCH /api/v1/patterns/:id
Update an existing pattern.

**Request Body:**
```json
{
  "pattern": {
    "confidence_weight": 2.5,
    "active": false,
    "metadata": {
      "updated_reason": "Poor performance"
    }
  }
}
```

**Response:**
```json
{
  "status": "success",
  "pattern": {
    "id": 1,
    "confidence_weight": 2.5,
    "active": false
  }
}
```

#### DELETE /api/v1/patterns/:id
Soft delete a pattern (deactivates it).

**Response:**
```json
{
  "status": "success",
  "message": "Pattern deactivated successfully"
}
```

### Categorization

#### POST /api/v1/categorization/suggest
Get category suggestions for expense data.

**Request Body:**
```json
{
  "merchant_name": "Walmart Supercenter",
  "description": "Grocery shopping",
  "amount": 125.50,
  "transaction_date": "2024-01-20",
  "max_suggestions": 3
}
```

**Response:**
```json
{
  "status": "success",
  "suggestions": [
    {
      "category": {
        "id": 5,
        "name": "Groceries",
        "color": "#10B981",
        "icon": "shopping-cart",
        "parent_id": null
      },
      "confidence": 0.850,
      "reason": "Merchant match: walmart",
      "type": "merchant",
      "pattern_id": 1
    },
    {
      "category": {
        "id": 12,
        "name": "Shopping",
        "color": "#8B5CF6",
        "icon": "shopping-bag",
        "parent_id": null
      },
      "confidence": 0.650,
      "reason": "Keyword match: shopping",
      "type": "keyword",
      "pattern_id": 45
    }
  ],
  "expense_data": {
    "merchant_name": "Walmart Supercenter",
    "description": "Grocery shopping",
    "amount": 125.5,
    "transaction_date": "2024-01-20T00:00:00Z"
  }
}
```

#### POST /api/v1/categorization/feedback
Submit feedback on categorization accuracy.

**Request Body:**
```json
{
  "feedback": {
    "expense_id": 1234,
    "category_id": 5,
    "pattern_id": 1,
    "was_correct": true,
    "confidence": 0.85,
    "feedback_type": "accepted"
  }
}
```

**Feedback Types:**
- `accepted`: User accepted the suggestion
- `rejected`: User rejected the suggestion
- `corrected`: User corrected to a different category
- `correction`: User is providing a correction

**Response:**
```json
{
  "status": "success",
  "feedback": {
    "id": 567,
    "expense_id": 1234,
    "category": {
      "id": 5,
      "name": "Groceries"
    },
    "pattern_id": 1,
    "feedback_type": "accepted",
    "was_correct": true,
    "confidence_score": 0.850,
    "created_at": "2024-01-20T15:30:00Z"
  },
  "improvement_suggestion": null
}
```

#### POST /api/v1/categorization/batch_suggest
Get suggestions for multiple expenses at once.

**Request Body:**
```json
{
  "expenses": [
    {
      "merchant_name": "Walmart",
      "amount": 50.00
    },
    {
      "merchant_name": "Target",
      "amount": 75.00
    },
    {
      "description": "Coffee at Starbucks",
      "amount": 5.50
    }
  ]
}
```

**Response:**
```json
{
  "status": "success",
  "results": [
    {
      "expense": {
        "merchant_name": "Walmart",
        "description": null,
        "amount": 50.0
      },
      "category_id": 5,
      "category_name": "Groceries",
      "confidence": 0.850
    },
    {
      "expense": {
        "merchant_name": "Target",
        "description": null,
        "amount": 75.0
      },
      "category_id": 5,
      "category_name": "Groceries",
      "confidence": 0.750
    },
    {
      "expense": {
        "merchant_name": null,
        "description": "Coffee at Starbucks",
        "amount": 5.5
      },
      "category_id": 8,
      "category_name": "Dining",
      "confidence": 0.900
    }
  ]
}
```

#### GET /api/v1/categorization/statistics
Get categorization system statistics.

**Response:**
```json
{
  "status": "success",
  "statistics": {
    "total_patterns": 250,
    "active_patterns": 230,
    "user_created_patterns": 45,
    "high_confidence_patterns": 120,
    "successful_patterns": 180,
    "frequently_used_patterns": 95,
    "recent_feedback_count": 342,
    "feedback_by_type": {
      "accepted": 280,
      "rejected": 35,
      "corrected": 20,
      "correction": 7
    },
    "average_success_rate": 0.825,
    "patterns_by_type": {
      "merchant": 100,
      "keyword": 75,
      "description": 40,
      "amount_range": 20,
      "regex": 10,
      "time": 5
    },
    "top_categories": [
      {
        "name": "Groceries",
        "pattern_count": 45
      },
      {
        "name": "Dining",
        "pattern_count": 38
      },
      {
        "name": "Transportation",
        "pattern_count": 32
      }
    ]
  }
}
```

## Error Responses

All endpoints return consistent error responses:

### 400 Bad Request
```json
{
  "error": "Parameter description",
  "status": 400
}
```

### 401 Unauthorized
```json
{
  "error": "Invalid or expired API token",
  "status": 401
}
```

### 404 Not Found
```json
{
  "error": "Record not found",
  "status": 404
}
```

### 422 Unprocessable Entity
```json
{
  "status": "error",
  "message": "Validation failed",
  "errors": [
    "Pattern type is not included in the list",
    "Pattern value has already been taken"
  ]
}
```

### 429 Too Many Requests
```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests. Please retry after 1705840200",
  "limit": 100,
  "period": 60,
  "retry_after": "1705840200"
}
```

## Pattern Types

### merchant
Matches against the merchant name field.
Example: `"walmart"`, `"target"`

### keyword
Matches against both merchant name and description fields.
Example: `"coffee"`, `"grocery"`

### description
Matches against the description field only.
Example: `"uber ride"`, `"monthly subscription"`

### amount_range
Matches transactions within a specific amount range.
Format: `"min-max"` (supports negative amounts)
Example: `"10.00-50.00"`, `"-100--50"`

### regex
Regular expression pattern matching.
Example: `"^AMZN.*"`, `"coffee|cafe|starbucks"`

### time
Matches based on transaction time patterns.
Values: `"morning"`, `"afternoon"`, `"evening"`, `"night"`, `"weekend"`, `"weekday"`
Time ranges: `"09:00-17:00"`

## Best Practices

1. **Pagination**: Always use pagination for list endpoints to improve performance.

2. **Caching**: API responses include cache headers. Respect them to reduce server load.

3. **Error Handling**: Always check the `status` field in responses and handle errors appropriately.

4. **Rate Limiting**: Implement exponential backoff when encountering rate limits.

5. **Batch Operations**: Use batch endpoints when processing multiple items to reduce API calls.

6. **Feedback Loop**: Always submit feedback on categorization suggestions to improve accuracy.

7. **Pattern Creation**: Before creating new patterns, search existing patterns to avoid duplicates.

8. **Confidence Thresholds**: Consider suggestions with confidence > 0.7 as reliable.