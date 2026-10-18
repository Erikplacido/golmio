class_name TestCase
extends RefCounted
## Base dos testes. Cada método test_* é executado por tests/run_tests.gd.

var failures: Array = []


func check(cond: bool, msg: String = "condição falsa") -> void:
	if not cond:
		failures.append(msg)


func check_eq(got: Variant, expected: Variant, msg: String = "") -> void:
	if got != expected:
		failures.append("%s — esperado %s, obtido %s" % [msg, str(expected), str(got)])


func check_near(got: float, expected: float, eps: float = 0.001, msg: String = "") -> void:
	if absf(got - expected) > eps:
		failures.append("%s — esperado %.4f, obtido %.4f" % [msg, expected, got])
