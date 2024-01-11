import { useState } from 'react';

type User = {
  name: string;
  email: string;
};

function User() {
  const [user, setUser] = useState<User | null>(null);

  const handleLogin = () => {
    setUser({
      name: 'Pepetrueno',
      email: 'pepe@pepe.com',
    });
  };

  const handleLogout = () => {
    setUser(null);
  };

  return (
    <div>
      <button onClick={handleLogin}>Login</button>
      <button onClick={handleLogout}>Logout</button>
      <div>User Name is: {user?.name} </div>
    </div>
  );
}

export default User;
