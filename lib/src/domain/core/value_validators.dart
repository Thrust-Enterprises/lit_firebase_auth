import 'package:dartz/dartz.dart';

import 'failures.dart';

// TODO improve this. Doesn't support spaces/tabs
Either<ValueFailure<String>, String> validateEmailAddress(String input) {
  const emailRegex =
      r"""^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+""";
  if (RegExp(emailRegex).hasMatch(input)) {
    return right(input);
  } else {
    return left(ValueFailure.invalidEmail(failedValue: input));
  }
}

Either<ValueFailure<String>, String> validateCellphoneNumber(String input) {
  const cellphoneRegex =
  r"""^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$""";
  if (RegExp(cellphoneRegex).hasMatch(input)) {
    return right(input);
  } else {
    return left(ValueFailure.invalidCellphoneNumber(failedValue: input));
  }
}

Either<ValueFailure<String>, String> validatePassword(String input) {
  if (input.length >= 6) {
    return right(input);
  } else {
    return left(ValueFailure.shortPassword(failedValue: input));
  }
}
