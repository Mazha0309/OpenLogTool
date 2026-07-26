BigInt toPlatformInt64(int value) => BigInt.from(value);

BigInt? toOptionalPlatformInt64(int? value) =>
    value == null ? null : BigInt.from(value);
