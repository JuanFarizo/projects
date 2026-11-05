#!/usr/bin/env bash
# Oracle for nv4j/dataquery.lua: Spring Data itself decides. A temp copy of tests/fixtures/jpa4 gets a repository with
# derived methods; `spring-boot:process-aot` starts the context in AOT mode, which fails with PropertyReferenceException
# for a bad derived name it only LOGS `ERROR ... Failed to contribute Repository method [...]` + PropertyReferenceException
# (mvn still exits 0). GOOD names: no such line; each BAD name (alone): the line, with Spring's own message, the same text
# nv4j.dataquery produces (Spring adds "; Did you mean 'x'" when a property is close: not copied). One Maven JVM per run: do not run while the machine is busy.
# Usage: tests/lib/oracle_dataquery.sh   (prints ORACLE PASS|FAIL lines, exit 1 on any FAIL)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/nv4j/oracle-dq-$$
JDK="$(nvim -l "$HERE/lib/jdk_home.lua" 25 2>/dev/null)"
[ -x "$JDK/bin/java" ] || { echo "FATAL: JDK 25 not found" >&2; exit 2; }
rm -rf "$W"; mkdir -p "$W"; cp -R "$HERE/fixtures/jpa4/." "$W/"; rm -rf "$W/target"
REPO="$W/src/main/java/jpa4/CustomerRepository.java"
run() { # $1 = method declarations; prints mvn output tail, returns mvn status
  cat > "$REPO" <<JAVA
package jpa4;
import java.util.*;
import org.springframework.data.jpa.repository.JpaRepository;
public interface CustomerRepository extends JpaRepository<Customer, Long> {
$1
}
JAVA
  JAVA_HOME="$JDK" mvn -q -f "$W/pom.xml" compile org.springframework.boot:spring-boot-maven-plugin:process-aot >"$W/out.log" 2>&1
}
rc=0
GOOD='
 Optional<Customer> findByEmail(String e);
 List<Customer> findByFullNameContainingIgnoreCaseOrderByEmailAsc(String e);
 List<Customer> findByEmailAndActive(String e, boolean a);
 List<Customer> findByEmailOrFullName(String e, String f);
 List<Customer> findByActiveTrue();
 List<Customer> findByAddressCity(String c);
 List<Customer> findByAddress_City(String c);
 List<Customer> findByAddressCityAndAddressZip(String c, String z);
 List<Customer> findByEmailOrderByFullNameAsc(String e);
 List<Customer> findTop3ByOrderByFullNameDesc();
 List<Customer> findAllByEmailIgnoreCase(String e);
 List<Customer> findDistinctByEmail(String e);
 long countByActive(boolean a);
 boolean existsByEmail(String e);
 List<Customer> findByEmailIsNotNull();
 List<Customer> findByIdIn(Collection<Long> ids);
 List<Customer> findByFullNameNot(String n);
 List<Customer> findByEmailAllIgnoreCase(String e);
 List<Customer> findAll();
'
if run "$GOOD" && ! grep -q "Failed to contribute Repository method" "$W/out.log" && [ -f "$W/target/spring-aot/main/resources/jpa4/CustomerRepository.json" ]; then echo "ORACLE PASS good_names (Spring contributed every method)"; else echo "ORACLE FAIL good_names: $(grep -m2 -E 'Failed to contribute|No property' "$W/out.log" | cut -c1-220)"; rc=1; fi
bad() { # $1 name  $2 expected message
  run " List<Customer> $1(String x);"
  if ! grep -qF "Failed to contribute Repository method [jpa4.CustomerRepository.$1(" "$W/out.log"; then echo "ORACLE FAIL bad_$1: Spring did not reject it"; rc=1; return; fi
  if grep -qF "$2" "$W/out.log"; then echo "ORACLE PASS bad_$1 ($2)"; else echo "ORACLE FAIL bad_$1: want '$2', got: $(grep -m1 -E 'No property|Caused by' "$W/out.log" | cut -c1-220)"; rc=1; fi
}
bad findByEmial "No property 'emial' found for type 'Customer'"
bad findByFullNme "No property 'fullNme' found for type 'Customer'"
bad findByAddressCty "No property 'cty' found for type 'Address'"
bad findByAddress_Cty "No property 'cty' found for type 'Address'"
rm -rf "$W"
exit $rc
