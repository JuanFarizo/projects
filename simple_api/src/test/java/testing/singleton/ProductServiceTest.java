package testing.singleton;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;

public class ProductServiceTest {

    @Test
    void testGetProduct() {
        ProductDAO productDAO = mock(ProductDAO.class);
        CacheManager cacheManager = mock(CacheManager.class);
        String productName = "Product1";
        Product product = new Product(productName, "Some Description");

        when(cacheManager.getValues(any(), any())).thenReturn(product);

        //ProductService productService = new ProductService(productDAO, cacheManager);

        //productService.getProduct(productName);
        Mockito.verify(productDAO, times(0)).getProduct(any());
    }

    @Test
    void givenValueExistInCache_WhenGetProduct_thenDAOIsNotCalled() {
        ProductDAO productDAO = mock(ProductDAO.class);
        CacheManager cacheManager = mock(CacheManager.class);

        String productName = "Product1";
        Product product = new Product(productName, "Some Description");

        try (MockedStatic<CacheManager> cacheManagerMock = mockStatic(CacheManager.class)) {
            cacheManagerMock.when(CacheManager::getInstance).thenReturn(cacheManager);
            when(cacheManager.getValues(any(), any())).thenReturn(product);
            ProductService productService = new ProductService(productDAO);
            productService.getProduct(productName);

            Mockito.verify(productDAO, times(0)).getProduct(productName);
        }
    }
}
