import React, { createContext, useState } from 'react';

export type AuthUser = {
  name: string;
  email: string;
};

type UserContextType = {
  user: AuthUser | null;
  setUser: React.Dispatch<React.SetStateAction<AuthUser | null>>;
};

type UserContextProviderProps = {
  children: React.ReactNode;
};

// prettier-ignore
export const UserContext = createContext({} as UserContextType); //Al crear el contexto pasamos nulo inicialmente
// Pero también puede ser un objeto del tipo AuthUser o null y una función setUser como utiliza el dispatcher
// {} as UserContextType we can prevent the check for null when use the context in the child


// prettier-ignore
export const UserContextProvider = ({children}: UserContextProviderProps) => {
// When the user Login the context should hold information about the user
    const [user, setUser] = useState<AuthUser | null>(null);

    return <UserContext.Provider value={{user, setUser: setUser}}>{children}</UserContext.Provider>  
}
