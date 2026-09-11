class ValidationError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def validate_transaction_fields(setup, tx_type: str, category: str, subcategory: str) -> None:
    if not setup.is_valid_category_for_type(tx_type, category):
        raise ValidationError(
            "invalid_category",
            f"Category '{category}' is not valid for type '{tx_type}'.",
        )
    if not setup.is_valid_subcategory(tx_type, category, subcategory):
        raise ValidationError(
            "invalid_subcategory",
            f"Subcategory '{subcategory}' does not belong to category '{category}'.",
        )
