void main() {
    // IO.println(addStrings("999", "11"));
    System.out.println("5".charAt(0));
}

public String addStrings(String a, String b) {
    StringBuilder sol = new StringBuilder();
    // Punteros para recorrer los strings de derecha a izquierda
    int leftC = a.length() - 1;
    int rightC = b.length() - 1;
    int carry = 0; // Acarreo de la suma

    // Iteramos mientras haya dígitos por procesar o un acarreo pendiente
    while (leftC >= 0 || rightC >= 0 || carry > 0) {
        int sum = carry;
        // Sumamos el dígito de 'a' si aún quedan caracteres
        if (leftC >= 0) {
            sum += a.charAt(leftC) - '0'; // Conversión de char a int de forma eficiente
            leftC--;
        }

        // Sumamos el dígito de 'b' si aún quedan caracteres
        if (rightC >= 0) {
            sum += b.charAt(rightC) - '0';
            rightC--;
        }

        // El nuevo dígito a agregar es el resto de la división por 10
        sol.append(sum % 10);

        // Calculamos el nuevo acarreo para la siguiente columna
        carry = sum / 10;
    }

    // Como sumamos de derecha a izquierda, el resultado está invertido
    return sol.reverse().toString();
}
