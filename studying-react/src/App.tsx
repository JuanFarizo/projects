import { useState } from 'react';
import Alert from './components/Alert';
import Button from './components/Button';
import ListGroup from './components/ListGroup';
import Input from './components/Input';
import ContainerStyle from './components/ContainerStyle';
import Counter from './components/Counter';
import { ThemeContextProvider } from './components/context/ThemeContext';
import { Box } from './components/context/Box';
import { UserContextProvider } from './components/context/UserContext';
import UserC from './components/context/UserC';
import MutableRef from './components/ref/MutableRef';
import { CounterClass } from './components/class/CounterClass';
import { Private } from './components/auth/Private';
import { Profile } from './components/auth/Profile';
import { List } from './components/generics/List';
import { RandomNumber } from './components/restriction/RandomNumber';
import { Text } from './components/polymorphic/Text';
import { Route, Routes } from 'react-router-dom';
import { Home } from './components/Home';
import { NavBar } from './NavBar';
import { Demo } from './components/demo/Demo';

function App() {
  let items = ['New York', 'Pergamino', 'Paris', 'Rancagua'];

  //Function variable writing
  const handleSelectedItem = (item: string) => {
    console.log(item);
  };
  const handleOnChangeInput = (event: React.ChangeEvent<HTMLInputElement>) => {
    console.log(event.timeStamp);
  };
  // Hook to manage state of the component
  const [alertVisible, setAlertVisibility] = useState(false);
  return (
    <>
      <NavBar />
      <Routes>
        <Route path="/" element={<Demo />}></Route>
        <Route
          path="/list-group"
          element={
            <div>
              <ListGroup
                items={items}
                heading="Cities"
                onSelectItem={handleSelectedItem}
              />
            </div>
          }
        ></Route>
      </Routes>

      {/* {alertVisible && (
        <Alert onClose={() => setAlertVisibility(false)}> My Alert</Alert>
      )}
      <div>
        <Button
          description="Simple Button"
          handleOnClick={() => setAlertVisibility(true)}
        />
      </div> */}
      {/*  <div>
        <ListGroup
          items={items}
          heading="Cities"
          onSelectItem={handleSelectedItem}
        />
      </div> */}

      {/* {
        <Input
          inputValue="Write your value here"
          handleOnChange={handleOnChangeInput}
        />
      }

      {
        <ContainerStyle
          style={{ border: '1px solid black', padding: '1erm' }}
        />
      }

      {<Counter />}

      {
        <ThemeContextProvider>
          <Box></Box>
        </ThemeContextProvider>
      }

      {
        <UserContextProvider>
          <UserC></UserC>
        </UserContextProvider>
      } */}

      {/*<MutableRef></MutableRef>*/}
      {/* {<CounterClass message="The counter value is"></CounterClass>} */}
      {/* {<Private isLogged={true} component={Profile}></Private>}

      {<List items={items} onClick={(item) => console.log(item)}></List>}

      {<RandomNumber value={10} isNegative></RandomNumber>}

      {
        <Text as="h1" size="lg" color="primary">
          May Frend
        </Text>
      } */}
    </>
  );
}

export default App;
