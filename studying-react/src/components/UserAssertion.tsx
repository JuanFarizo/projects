import { useState } from 'react';

type User = {
  name: string;
  email: string;
};

function UserAssertion() {
  const [user, setUser] = useState<User>({} as User);

  const handleLogin = () => {
    setUser({
      name: 'Pepetrueno',
      email: 'pepe@pepe.com',
    });
  };

  return (
    <div>
      <button onClick={handleLogin}>Login</button>
      <div>User Name is: {user.name} </div>
    </div>
  );
}

export default User;
