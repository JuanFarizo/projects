import React from 'react';
import { Login } from './Login';
import { ProfileProps } from './Profile';

type Props = {
  isLogged: boolean;
  component: React.ComponentType<ProfileProps>; //For type the Componen Props and between
}; // the diamons the type of the props that te component accepts in this case the component
// is Profile and has a type of Props ProfileProps

export const Private = ({ isLogged, component: Component }: Props) => {
  if (isLogged) {
    return <Component name="PepeTrueno"></Component>;
  } else {
    return <Login></Login>;
  }
};
